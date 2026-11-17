#!/usr/bin/env bash
# Penpot.app ve Penpot Güncelle.app'i derleyip verilen klasöre koyar.
# Kullanım: build-all.sh <kurulum klasörü (Sistem'in bir üstü)>
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${1:?kurulum klasörü gerekli}"
ICON="$HERE/Penpot.icns"

bash "$HERE/build.sh" "$ROOT/Penpot.app" "$ICON"

# Penpot Güncelle: AppleScript uygulaması
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
osacompile -o "$TMP/Penpot Güncelle.app" "$HERE/PenpotGuncelle.applescript"
cp "$ICON" "$TMP/Penpot Güncelle.app/Contents/Resources/applet.icns"
codesign -f -s - "$TMP/Penpot Güncelle.app" >/dev/null 2>&1
rm -rf "$ROOT/Penpot Güncelle.app"; mv "$TMP/Penpot Güncelle.app" "$ROOT/Penpot Güncelle.app"; touch "$ROOT/Penpot Güncelle.app"
echo "Derlendi: $ROOT/Penpot Güncelle.app"
