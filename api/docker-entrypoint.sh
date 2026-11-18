#!/bin/sh
# Entrypoint do container de desenvolvimento.
set -e

cd /app

# Mantém node_modules (volume do container) sincronizado com o package.json.
if [ ! -f node_modules/.package-lock.json ] || [ package.json -nt node_modules/.package-lock.json ] || [ package-lock.json -nt node_modules/.package-lock.json ]; then
  echo "[entrypoint] Instalando dependências..."
  npm install --no-audit --no-fund
fi

npx prisma generate
npx prisma migrate deploy

if [ "$SEED_ON_START" = "true" ]; then
  npx prisma db seed
fi

exec "$@"
