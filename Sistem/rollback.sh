#!/usr/bin/env bash
# Son güncellemeyi geri alır: eski sürüm dosyalarını ve güncelleme öncesi veritabanı yedeğini geri yükler.
set -euo pipefail
L="$(cd "$(dirname "$0")" && pwd)"; cd "$L"
source "$L/penpot.env"

[ -d "$L/backend.old" ] && [ -d "$L/frontend.old" ] || { echo "Geri alınacak eski sürüm yok."; exit 1; }
DUMP="$(ls -t "$L"/backups/*.dump 2>/dev/null | head -1)"
[ -n "$DUMP" ] || { echo "Veritabanı yedeği bulunamadı."; exit 1; }

echo "Eski sürüme dönülecek: $(cat "$L/backend.old/version.txt")"
echo "Geri yüklenecek yedek: $DUMP"
echo "Güncellemeden sonra yaptığınız değişiklikler kaybolur."
read -r -p "Devam edilsin mi? [e/H] " ok
case "$ok" in e|E|evet|Evet) ;; *) echo "İptal edildi."; exit 0;; esac

"$L/stop.sh" >/dev/null
rm -rf "$L/backend" "$L/frontend"
mv "$L/backend.old" "$L/backend"; mv "$L/frontend.old" "$L/frontend"
for c in exporter mcp; do
  if [ -d "$L/$c.old" ]; then rm -rf "$L/$c"; mv "$L/$c.old" "$L/$c"; fi
done
[ -d "$L/mcp" ] && "$L/tools/mcp-sharp-macos.sh" "$L/mcp" >/dev/null 2>&1 || true

pg_ctl -D "$L/data/pg" -l "$L/logs/postgres.log" -o "-p 5432 -k /tmp -h 127.0.0.1" -w start >/dev/null
psql -h 127.0.0.1 -U postgres -c "DROP DATABASE penpot;" >/dev/null
psql -h 127.0.0.1 -U postgres -c "CREATE DATABASE penpot OWNER penpot;" >/dev/null
pg_restore -h 127.0.0.1 -U penpot -d penpot "$DUMP"

"$L/start.sh"
echo "Geri alındı: $(cat "$L/backend/version.txt")"
