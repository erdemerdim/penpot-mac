#!/usr/bin/env bash
# GitHub deposundaki son değişiklikleri bu Mac'e alır (git pull) ve gerekenleri uygular:
#   - uygulama kaynakları değiştiyse Penpot.app / Penpot Güncelle.app yeniden derlenir
#   - bileşen sürümleri (Sistem/surumler.env) değiştiyse ilgili bileşenler yeniden kurulur
# Çıktının son satırı Penpot Güncelle için özet: "DEPO: ..." 
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
if [ ! -d .git ] || [ -z "$(git remote 2>/dev/null)" ]; then echo "DEPO: bağlı değil"; exit 0; fi

OLD="$(git rev-parse HEAD)"
if ! OUT="$(git pull --ff-only 2>&1)"; then
  echo "$OUT"
  echo "DEPO: HATA - depo güncellenemedi. Bu Mac'te gönderilmemiş değişiklikler olabilir; önce ./gonder.sh çalıştırın."
  exit 1
fi
NEW="$(git rev-parse HEAD)"
if [ "$OLD" = "$NEW" ]; then echo "DEPO: zaten güncel"; exit 0; fi

CHANGED="$(git diff --name-only "$OLD" "$NEW")"
echo "Değişen dosyalar:"; echo "$CHANGED" | sed 's/^/  /'
chmod +x "$ROOT"/*.sh Sistem/*.sh Sistem/tools/*.sh Sistem/tools/app/*.sh Sistem/bin/convert 2>/dev/null || true

if echo "$CHANGED" | grep -qE '^(Sistem/surumler\.env|Sistem/tools/(magick|pdfunite)\.swift|kurulum\.sh)$'; then
  # Bileşen sürümleri ya da yardımcı araçlar değişti: kurulum betiği yalnızca farkları uygular
  bash "$ROOT/kurulum.sh" --guncelle || { echo "DEPO: HATA - bileşenler güncellenemedi"; exit 1; }
elif echo "$CHANGED" | grep -q '^Sistem/tools/app/'; then
  bash "$ROOT/Sistem/tools/app/build-all.sh" "$ROOT" || { echo "DEPO: HATA - uygulama derlenemedi"; exit 1; }
fi
echo "DEPO: güncellendi ($(git log -1 --format='%h %s'))"
