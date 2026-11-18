#!/usr/bin/env bash
# Tek parça Penpot.app (DMG) için: her açılışta Penpot.app tarafından çalıştırılır.
# Paketin içindeki bileşenlere (salt okunur) bağlantılar ve kullanıcının veri klasörünü hazırlar:
#   ~/Library/Application Support/Penpot/Sistem/
#     data/, logs/, penpot.env   -> bu Mac'e özel (tasarımlar, veritabanı, gizli değerler)
#     jdk, backend, start.sh ... -> uygulama paketinin içine bağlantı
# Böylece start.sh/stop.sh kurulum klasöründeki gibi aynen çalışır. Uygulama taşınırsa
# bağlantılar bir sonraki açılışta yenilenir.
set -euo pipefail
RT="$(cd "$(dirname "$0")" && pwd)"            # paketin içindeki runtime klasörü
S="$HOME/Library/Application Support/Penpot/Sistem"
mkdir -p "$S/data" "$S/logs"

for x in jdk node pgsql valkey backend frontend exporter browsers mcp bin patches tools \
         start.sh stop.sh proxy.mjs penpot.env.example; do
  [ -e "$RT/$x" ] || continue
  if [ -e "$S/$x" ] && [ ! -L "$S/$x" ]; then echo "Beklenmeyen dosya: $S/$x" >&2; exit 1; fi
  ln -sfn "$RT/$x" "$S/$x"
done

# İlk açılış: bu Mac'e özel gizli değerler
if [ ! -f "$S/penpot.env" ]; then
  SECRET="$(openssl rand -hex 32)"; DBPW="$(openssl rand -hex 16)"
  sed -e "s/__SECRET_KEY__/$SECRET/" -e "s/__DB_PASSWORD__/$DBPW/" "$RT/penpot.env.example" > "$S/penpot.env.tmp"
  chmod 600 "$S/penpot.env.tmp"; mv "$S/penpot.env.tmp" "$S/penpot.env"
  echo "penpot.env oluşturuldu"
fi

# Güncelleme: özellik bayraklarını (gizli değil) paketteki şablonla eşitle. Aksi hâlde eski
# sürümden gelen penpot.env yeni bayrakları almaz ve start.sh paketin içindeki config.js'i
# yeniden yazıp uygulamanın imzasını bozar.
YENI="$(grep -m1 '^export PENPOT_FLAGS=' "$RT/penpot.env.example" || true)"
if [ -n "$YENI" ] && ! grep -qxF "$YENI" "$S/penpot.env"; then
  awk -v y="$YENI" '/^export PENPOT_FLAGS=/{print y; b=1; next} {print} END{if(!b) print y}' "$S/penpot.env" > "$S/penpot.env.tmp"
  chmod 600 "$S/penpot.env.tmp"; mv "$S/penpot.env.tmp" "$S/penpot.env"
  echo "penpot.env bayrakları güncellendi"
fi

# Hızlı açılış: önceden derlenmiş Penpot kodu pakette hazır gelir (tools/aot-compile.sh çıktısı)
STAMP="$(stat -L -f "%z-%m" "$RT/backend/penpot.jar")"
if [ -f "$RT/seed/penpot-classes.jar" ] && [ "$(cat "$S/data/penpot-classes.stamp" 2>/dev/null)" != "$STAMP" ]; then
  cp "$RT/seed/penpot-classes.jar" "$S/data/penpot-classes.jar"
  echo "$STAMP" > "$S/data/penpot-classes.stamp"
  rm -f "$S/data/penpot-fast.aot" "$S/data/penpot-src.aot"   # Java açılış önbelleği yeniden oluşsun
  echo "Önceden derlenmiş kod kopyalandı"
fi
