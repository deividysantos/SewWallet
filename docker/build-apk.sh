#!/bin/sh
# Gera o APK de release e copia para /out (pasta releases/ do projeto).
# Uso: docker compose --env-file .env.prod --profile tools run --rm apk
set -e

cd /app
API_URL="${API_URL:-http://localhost:3000}"

yes | flutter doctor --android-licenses >/dev/null 2>&1 || true
flutter pub get
flutter build apk --release --dart-define=API_URL="$API_URL"

version=$(grep '^version:' pubspec.yaml | awk '{print $2}' | tr '+' '-')
out="/out/sewwallet-${version}.apk"
mkdir -p /out
cp build/app/outputs/flutter-apk/app-release.apk "$out"
echo "[apk] Pronto: releases/$(basename "$out")  (API padrão: $API_URL)"
