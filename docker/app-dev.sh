#!/bin/sh
# Desenvolvimento do app: compila para web, serve em :8080 e recompila
# sozinho quando algo em lib/, assets/ ou pubspec.yaml muda.
# Depois de salvar, é só recarregar a página (F5).

cd /app
API_URL="${API_URL:-http://localhost:3000}"

fingerprint() {
  find lib assets web pubspec.yaml -type f 2>/dev/null -exec stat -c '%Y %s %n' {} + | sort | md5sum
}

build() {
  echo "[app] Compilando..."
  start=$(date +%s)
  if flutter build web --release --dart-define=API_URL="$API_URL" --no-wasm-dry-run --pwa-strategy=none >/tmp/build.log 2>&1; then
    echo "[app] Pronto em $(( $(date +%s) - start ))s -> http://localhost:8080"
  else
    echo "[app] ERRO na compilação:"
    tail -n 40 /tmp/build.log
  fi
}

flutter pub get
build
dhttpd --host 0.0.0.0 --port 8080 --path build/web --headers "Cache-Control=no-store" &

last=$(fingerprint)
while true; do
  sleep 2
  now=$(fingerprint)
  if [ "$now" != "$last" ]; then
    last="$now"
    flutter pub get >/dev/null 2>&1
    build
  fi
done
