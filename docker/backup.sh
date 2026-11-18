#!/bin/sh
# Backup diário do banco de produção em ./backups (pg_dump compactado).
# Mantém os últimos BACKUP_KEEP_DAYS dias. Roda no container "backup".
set -e

KEEP="${BACKUP_KEEP_DAYS:-30}"
HOUR="${BACKUP_HOUR:-03}"
mkdir -p /backups

dump() {
  file="/backups/sewwallet-$(date +%Y-%m-%d_%H%M).sql.gz"
  if pg_dump -h db -U "$POSTGRES_USER" -d "$POSTGRES_DB" | gzip > "$file.tmp"; then
    mv "$file.tmp" "$file"
    echo "[backup] OK: $file"
  else
    rm -f "$file.tmp"
    echo "[backup] ERRO ao gerar backup"
  fi
  find /backups -name 'sewwallet-*.sql.gz' -mtime +"$KEEP" -delete
}

# Um backup ao subir e depois um por dia no horário BACKUP_HOUR.
dump
last_day=$(date +%F)
while true; do
  sleep 600
  if [ "$(date +%H)" = "$HOUR" ] && [ "$(date +%F)" != "$last_day" ]; then
    dump
    last_day=$(date +%F)
  fi
done
