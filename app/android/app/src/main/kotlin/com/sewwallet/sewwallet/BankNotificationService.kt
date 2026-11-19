package com.sewwallet.sewwallet

import android.app.Notification
import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Lê as notificações dos apps de banco marcados no SewWallet e envia para a API
 * (POST /suggestions/notifications), que interpreta com IA e cria sugestões / dá baixa.
 *
 * Roda mesmo com o app fechado. O que não conseguir enviar (sem Tailscale, servidor fora)
 * fica numa fila e vai na próxima notificação ou quando o app abrir.
 *
 * Configuração vem do shared_preferences do Flutter (arquivo FlutterSharedPreferences, chaves "flutter.*"):
 * notifications.enabled (bool), notifications.apps (pacotes separados por vírgula), token e serverUrl.
 */
class BankNotificationService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        try {
            handle(applicationContext, sbn)
        } catch (_: Throwable) {
            // Nunca derrubar o serviço por causa de uma notificação estranha.
        }
    }

    companion object {
        private const val NATIVE_PREFS = "sewwallet_notifications"
        private const val KEY_QUEUE = "queue"
        private const val KEY_LOG = "log"
        private const val KEY_SEEN = "seen"
        private const val MAX_QUEUE = 200
        private const val MAX_LOG = 40

        private val money = Regex("""R\$\s?-?\d""")
        private val lock = Any()

        fun flutterPrefs(ctx: Context): SharedPreferences =
            ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        fun nativePrefs(ctx: Context): SharedPreferences =
            ctx.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)

        private fun appLabel(ctx: Context, pkg: String): String = try {
            val pm = ctx.packageManager
            pm.getApplicationLabel(pm.getApplicationInfo(pkg, PackageManager.GET_META_DATA)).toString()
        } catch (_: Exception) {
            pkg
        }

        private fun isoNow(millis: Long): String =
            SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.US).format(Date(millis))

        fun handle(ctx: Context, sbn: StatusBarNotification) {
            val pkg = sbn.packageName ?: return
            if (pkg == ctx.packageName) return
            val n = sbn.notification ?: return
            if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
            val extras = n.extras ?: return
            val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
            val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
                ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString() ?: return
            // Só interessa o que fala de dinheiro.
            if (!money.containsMatchIn(text) && !(title != null && money.containsMatchIn(title))) return

            val fp = flutterPrefs(ctx)
            val label = appLabel(ctx, pkg)
            rememberSeen(ctx, pkg, label)
            if (!fp.getBoolean("flutter.notifications.enabled", false)) return
            val apps = (fp.getString("flutter.notifications.apps", "") ?: "").split(',').map { it.trim() }.toSet()
            if (pkg !in apps) return

            val item = JSONObject()
                .put("app", pkg)
                .put("appName", label)
                .put("title", title ?: JSONObject.NULL)
                .put("text", text)
                .put("postedAt", isoNow(sbn.postTime))
                .put("key", sbn.key)
            enqueue(ctx, item)
            // O registro local ganha a linha quando a API aceitar (ou recusar); até lá, conta na fila.
            Thread { flush(ctx) }.start()
        }

        private fun rememberSeen(ctx: Context, pkg: String, label: String) {
            synchronized(lock) {
                val p = nativePrefs(ctx)
                val seen = JSONObject(p.getString(KEY_SEEN, "{}") ?: "{}")
                if (!seen.has(pkg)) {
                    seen.put(pkg, label)
                    p.edit().putString(KEY_SEEN, seen.toString()).apply()
                }
            }
        }

        private fun enqueue(ctx: Context, item: JSONObject) {
            synchronized(lock) {
                val p = nativePrefs(ctx)
                val q = JSONArray(p.getString(KEY_QUEUE, "[]") ?: "[]")
                q.put(item)
                while (q.length() > MAX_QUEUE) q.remove(0)
                p.edit().putString(KEY_QUEUE, q.toString()).apply()
            }
        }

        fun addLog(ctx: Context, item: JSONObject, result: String) {
            synchronized(lock) {
                val p = nativePrefs(ctx)
                val log = JSONArray(p.getString(KEY_LOG, "[]") ?: "[]")
                val entry = JSONObject()
                    .put("appName", item.optString("appName"))
                    .put("title", item.opt("title"))
                    .put("text", item.optString("text"))
                    .put("postedAt", item.optString("postedAt"))
                    .put("result", result)
                log.put(entry)
                while (log.length() > MAX_LOG) log.remove(0)
                p.edit().putString(KEY_LOG, log.toString()).apply()
            }
        }

        fun queueSize(ctx: Context): Int =
            JSONArray(nativePrefs(ctx).getString(KEY_QUEUE, "[]") ?: "[]").length()

        fun log(ctx: Context): String = nativePrefs(ctx).getString(KEY_LOG, "[]") ?: "[]"

        fun seen(ctx: Context): String = nativePrefs(ctx).getString(KEY_SEEN, "{}") ?: "{}"

        /** Envia a fila. Retorna quantas foram aceitas pela API. Uma por vez, na ordem. */
        fun flush(ctx: Context): Int {
            val fp = flutterPrefs(ctx)
            val token = fp.getString("flutter.token", null) ?: return 0
            val server = (fp.getString("flutter.serverUrl", null) ?: return 0).trimEnd('/')
            var sent = 0
            synchronized(lock) {
                val p = nativePrefs(ctx)
                val q = JSONArray(p.getString(KEY_QUEUE, "[]") ?: "[]")
                val keep = JSONArray()
                var stop = false
                for (i in 0 until q.length()) {
                    val item = q.getJSONObject(i)
                    if (stop) { keep.put(item); continue }
                    val code = post("$server/suggestions/notifications", token, item)
                    when {
                        code in 200..299 -> { sent++; addLog(ctx, item, "enviada") }
                        // Erro da própria notificação (dados inválidos): não adianta tentar de novo.
                        code == 400 || code == 413 || code == 422 -> addLog(ctx, item, "recusada ($code)")
                        // Sem rede, servidor fora, login vencido: para e tenta depois.
                        else -> { keep.put(item); stop = true }
                    }
                }
                p.edit().putString(KEY_QUEUE, keep.toString()).apply()
            }
            return sent
        }

        private fun post(url: String, token: String, body: JSONObject): Int = try {
            val c = URL(url).openConnection() as HttpURLConnection
            c.requestMethod = "POST"
            c.connectTimeout = 15_000
            c.readTimeout = 60_000
            c.doOutput = true
            c.setRequestProperty("Content-Type", "application/json; charset=utf-8")
            c.setRequestProperty("Authorization", "Bearer $token")
            c.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            val code = c.responseCode
            c.disconnect()
            code
        } catch (_: Exception) {
            -1
        }
    }
}
