package com.sewwallet.sewwallet

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Canal da leitura de notificações (ver BankNotificationService).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sewwallet/notifications").setMethodCallHandler { call, result ->
            val ctx = applicationContext
            when (call.method) {
                "isGranted" -> {
                    val enabled = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: ""
                    result.success(enabled.split(':').any { it.startsWith("$packageName/") })
                }
                "openSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(null)
                }
                "openAppDetails" -> {
                    startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    result.success(null)
                }
                "queueSize" -> result.success(BankNotificationService.queueSize(ctx))
                "log" -> result.success(BankNotificationService.log(ctx))
                "seenApps" -> result.success(BankNotificationService.seen(ctx))
                "flush" -> Thread {
                    val sent = BankNotificationService.flush(ctx)
                    runOnUiThread { result.success(sent) }
                }.start()
                else -> result.notImplemented()
            }
        }
    }
}
