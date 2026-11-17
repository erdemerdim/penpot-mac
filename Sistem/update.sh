#!/usr/bin/env bash
# Penpot'u günceller.
#   ./update.sh            -> en son sürüme günceller
#   ./update.sh 2.19.0     -> belirli bir sürüme günceller
#   ./update.sh --check    -> sadece yeni sürüm var mı bakar
#   ./update.sh --yes      -> onay sormadan en son sürüme günceller (Penpot Güncelle.app bunu kullanır)
set -euo pipefail
L="$(cd "$(dirname "$0")" && pwd)"; cd "$L"
source "$L/penpot.env"

CURRENT="$(cat "$L/backend/version.txt" 2>/dev/null || echo bilinmiyor)"
LATEST="$(curl -fsSL "https://hub.docker.com/v2/repositories/penpotapp/backend/tags?page_size=100&ordering=last_updated" \
  | python3 -I -c 'import sys,json,re
t=[r["name"] for r in json.load(sys.stdin)["results"] if re.fullmatch(r"\d+\.\d+\.\d+",r["name"])]
print(sorted(t,key=lambda s:tuple(map(int,s.split("."))))[-1])')"

echo "Kurulu sürüm: $CURRENT"
echo "En son sürüm: $LATEST"

if [ "${1:-}" = "--check" ]; then
  [ "$CURRENT" = "$LATEST" ] && echo "Penpot güncel." || echo "Yeni sürüm var. Güncellemek için: $L/update.sh"
  exit 0
fi

YES=0
if [ "${1:-}" = "--yes" ]; then YES=1; shift; fi

TARGET="${1:-$LATEST}"
if [ "$TARGET" = "$CURRENT" ]; then echo "Penpot zaten $CURRENT sürümünde, güncelleme gerekmiyor."; exit 0; fi

if [ "$YES" != "1" ]; then
  read -r -p "Penpot $CURRENT -> $TARGET sürümüne güncellensin mi? [e/H] " ok
  case "$ok" in e|E|evet|Evet) ;; *) echo "İptal edildi."; exit 0;; esac
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "1/6 Yeni sürüm indiriliyor (backend, frontend, exporter, MCP)..."
"$L/tools/pull_image.sh" penpotapp/backend "$TARGET" "$TMP/backend" 2>/dev/null
"$L/tools/pull_image.sh" penpotapp/frontend "$TARGET" "$TMP/frontend" 2>/dev/null
[ -f "$TMP/backend/opt/penpot/backend/penpot.jar" ] && [ -f "$TMP/frontend/var/www/app/index.html" ] \
  || { echo "İndirme başarısız oldu, mevcut kuruluma dokunulmadı."; exit 1; }
# Exporter ve MCP: indirilemezse ya da macOS'a hazırlanamazsa mevcut sürümleri korunur
"$L/tools/pull_image.sh" penpotapp/exporter "$TARGET" "$TMP/exporterimg" 2>/dev/null || true
"$L/tools/pull_image.sh" penpotapp/mcp "$TARGET" "$TMP/mcpimg" 2>/dev/null || true

echo "2/6 Exporter ve MCP macOS için hazırlanıyor..."
NEW_EXPORTER=0; NEW_MCP=0
if [ -f "$TMP/exporterimg/opt/penpot/exporter/app.js" ]; then
  cp -R "$TMP/exporterimg/opt/penpot/exporter" "$TMP/exporter"
  # Yeni exporter'ın istediği Chromium sürümü yoksa indirilir (varsa hiçbir şey yapmaz)
  if (cd "$TMP/exporter" && PLAYWRIGHT_BROWSERS_PATH="$L/browsers" node node_modules/playwright/cli.js install --only-shell chromium >/dev/null 2>&1); then
    NEW_EXPORTER=1
  else
    echo "   Uyarı: Exporter için Chromium indirilemedi; mevcut exporter korunacak."
  fi
else
  echo "   Uyarı: Exporter $TARGET indirilemedi; mevcut exporter korunacak."
fi
if [ -f "$TMP/mcpimg/opt/penpot/mcp/index.js" ]; then
  cp -R "$TMP/mcpimg/opt/penpot/mcp" "$TMP/mcp"
  if "$L/tools/mcp-sharp-macos.sh" "$TMP/mcp" >/dev/null 2>&1; then
    NEW_MCP=1
  else
    echo "   Uyarı: MCP görsel kütüphanesi macOS için hazırlanamadı; mevcut MCP korunacak."
  fi
else
  echo "   Uyarı: MCP $TARGET indirilemedi; mevcut MCP korunacak."
fi
rm -rf "$TMP/exporterimg" "$TMP/mcpimg"

echo "3/6 Veritabanı yedekleniyor..."
"$L/start.sh" >/dev/null 2>&1 || true
mkdir -p "$L/backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
pg_dump -h 127.0.0.1 -U penpot -d penpot -Fc -f "$L/backups/penpot-$CURRENT-$STAMP.dump"

echo "4/6 Penpot durduruluyor..."
"$L/stop.sh" >/dev/null

echo "5/6 Dosyalar değiştiriliyor (eski sürüm saklanıyor)..."
rm -rf "$L/backend.old" "$L/frontend.old" "$L/exporter.old" "$L/mcp.old"
mv "$L/backend" "$L/backend.old"; mv "$L/frontend" "$L/frontend.old"
cp -R "$TMP/backend/opt/penpot/backend" "$L/backend"
cp -R "$TMP/frontend/var/www/app" "$L/frontend"
if [ "$NEW_EXPORTER" = 1 ]; then
  [ -d "$L/exporter" ] && mv "$L/exporter" "$L/exporter.old"
  mv "$TMP/exporter" "$L/exporter"
fi
if [ "$NEW_MCP" = 1 ]; then
  [ -d "$L/mcp" ] && mv "$L/mcp" "$L/mcp.old"
  mv "$TMP/mcp" "$L/mcp"
  # Taşınan klasörde sharp bağlantılarını yeni yere göre yenile
  "$L/tools/mcp-sharp-macos.sh" "$L/mcp" >/dev/null 2>&1 || echo "   Uyarı: MCP görsel kütüphanesi bağlanamadı."
fi

echo "6/6 Penpot başlatılıyor (veritabanı güncellemesi birkaç dakika sürebilir)..."
if "$L/start.sh"; then
  echo "Güncelleme tamam: $(cat "$L/backend/version.txt")"
  # Diğer Mac de aynı sürümü kursun diye sürüm dosyasına yaz (./gonder.sh ile depoya gider)
  [ -f "$L/surumler.env" ] && sed -i '' "s/^PENPOT_VERSION=.*/PENPOT_VERSION=$(cat "$L/backend/version.txt")/" "$L/surumler.env"
  echo "Exporter: $(cat "$L/exporter/version.txt" 2>/dev/null || echo '?'), MCP: $(cat "$L/mcp/version.txt" 2>/dev/null || echo '?')"
  echo "Yedek: $L/backups/penpot-$CURRENT-$STAMP.dump"
else
  echo "Yeni sürüm açılmadı. Geri almak için: $L/rollback.sh"
  exit 1
fi
