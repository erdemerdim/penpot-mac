#!/usr/bin/env bash
# İndirilip doğrudan kullanılabilen tek parça Penpot.app'i ve onu içeren DMG'yi oluşturur.
# Bileşenler bu kurulumun Sistem klasöründen alınır (önce kurulum.sh çalışmış olmalı);
# kişisel veriler (Sistem/data, logs, penpot.env…) pakete GİRMEZ.
#
#   Sistem/tools/app/dmg-olustur.sh            -> dist/Penpot-<APP_VERSION>.dmg
# Sürüm: Sistem/surumler.env içindeki APP_VERSION (Release etiketi v<APP_VERSION>).
#
# Uygulama açılınca verilerini ~/Library/Application Support/Penpot altında tutar (hazirla.sh).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
L="$(cd "$HERE/../.." && pwd)"          # Sistem
ROOT="$(cd "$L/.." && pwd)"
source "$L/surumler.env"
PV="$(cat "$L/backend/version.txt")"
OUTDIR="$ROOT/dist"; DMG="$OUTDIR/Penpot-$APP_VERSION.dmg"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
say() { printf '\n==> %s\n' "$*"; }

for c in jdk pgsql valkey backend frontend exporter browsers mcp bin/magick bin/pdfunite; do
  [ -e "$L/$c" ] || { echo "Eksik bileşen: Sistem/$c (önce kurulum.sh çalıştırın)" >&2; exit 1; }
done

# Node: kurulumda Sistem/node varsa o, yoksa surumler.env'deki sürüm indirilir
NODE_SRC="$L/node"
if [ ! -x "$NODE_SRC/bin/node" ]; then
  say "Node.js $NODE_VERSION indiriliyor"
  curl -fsSL -o "$WORK/node.txz" "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-darwin-arm64.tar.xz"
  [ "$(shasum -a 256 "$WORK/node.txz" | cut -d' ' -f1)" = "$NODE_SHA256" ] || { echo "Node doğrulaması başarısız" >&2; exit 1; }
  tar -xJf "$WORK/node.txz" -C "$WORK"; NODE_SRC="$WORK/node-v$NODE_VERSION-darwin-arm64"
fi

say "Penpot.app derleniyor"
PENPOT_BUNDLE_ID="io.github.erdemerdim.penpot-mac" PENPOT_APP_VERSION="$APP_VERSION" \
  PENPOT_VERSION_INFO="$PV" PENPOT_UPDATE_REPO="$UPDATE_REPO" \
  bash "$HERE/build.sh" "$WORK/Penpot.app" "$HERE/Penpot.icns" >/dev/null 2>&1
RT="$WORK/Penpot.app/Contents/Resources/runtime"
mkdir -p "$RT/bin" "$RT/tools" "$RT/seed"

say "Bileşenler pakete kopyalanıyor"
R="rsync -a --delete --exclude .DS_Store"
$R --exclude '/Contents/Home/jmods' --exclude '/Contents/Home/demo' --exclude '/Contents/Home/man' \
   --exclude '/Contents/Home/include' --exclude '/Contents/Home/lib/src.zip' --exclude '/Contents/_CodeSignature' \
   --exclude '.kurulum-surumu' "$L/jdk/" "$RT/jdk/"
mkdir -p "$RT/node/bin"; cp "$NODE_SRC/bin/node" "$RT/node/bin/node"; cp "$NODE_SRC/LICENSE" "$RT/node/LICENSE"
$R --exclude '/include' --exclude '/lib/*.a' --exclude '/lib/pkgconfig' --exclude '/lib/pgxs' --exclude '/share/doc' \
   --exclude '.kurulum-surumu' "$L/pgsql/" "$RT/pgsql/"
$R --exclude '.kurulum-surumu' "$L/valkey/" "$RT/valkey/"
$R "$L/backend/" "$RT/backend/"
$R --exclude '*.map' "$L/frontend/" "$RT/frontend/"
$R --exclude '*.map' "$L/exporter/" "$RT/exporter/"
$R --exclude '*.map' --exclude '/logs' "$L/mcp/" "$RT/mcp/"
$R --exclude '/.links' "$L/browsers/" "$RT/browsers/"
cp "$L/bin/convert" "$L/bin/magick" "$L/bin/pdfunite" "$RT/bin/"
cp -R "$L/patches" "$RT/patches"
cp "$L/start.sh" "$L/stop.sh" "$L/proxy.mjs" "$L/penpot.env.example" "$RT/"
cp "$L/tools/aot-compile.sh" "$RT/tools/"
cp "$HERE/hazirla.sh" "$RT/hazirla.sh"
cp "$ROOT/LICENSE" "$ROOT/NOTICE.md" "$WORK/Penpot.app/Contents/Resources/"
chmod +x "$RT"/*.sh "$RT"/tools/*.sh "$RT"/bin/*

# Arayüz ayarı pakette hazır yazılır (start.sh paketin içindeki dosyayı değiştirmesin)
FLAGS="$(sed -n 's/^export PENPOT_FLAGS="\(.*\)"$/\1/p' "$L/penpot.env.example")"
URI="$(sed -n 's/^export PENPOT_PUBLIC_URI="\(.*\)"$/\1/p' "$L/penpot.env.example")"
printf '// Frontend configuration\nvar penpotFlags = "%s";\nvar penpotPublicURI = "%s";\n' "$FLAGS" "$URI" > "$RT/frontend/js/config.js"

# Önceden derlenmiş Penpot kodu (hızlı ilk açılış); bu kurulumdakiyle aynı penpot.jar içinse
if [ -f "$L/data/penpot-classes.jar" ] && [ "$(cat "$L/data/penpot-classes.stamp" 2>/dev/null)" = "$(stat -f "%z-%m" "$L/backend/penpot.jar")" ]; then
  cp "$L/data/penpot-classes.jar" "$RT/seed/"
else
  echo "Uyarı: önceden derlenmiş kod yok; ilk açılış daha uzun sürer (tools/aot-compile.sh)." >&2
fi

say "Kişisel veri kontrolü"
LEAK=0
for p in data logs backups chrome-profile penpot.env; do [ -e "$RT/$p" ] && { echo "HATA: pakette $p var" >&2; LEAK=1; }; done
if grep -rIl --exclude-dir=node_modules "$HOME" "$RT" 2>/dev/null | head -5 | grep .; then
  echo "HATA: pakette bu kullanıcının klasör yolu geçen dosyalar var (yukarıda)" >&2; LEAK=1
fi
[ "$LEAK" = 0 ] || exit 1
echo "Temiz."

say "İmzalanıyor (yerel, ad-hoc)"
codesign -f -s - "$WORK/Penpot.app"
codesign --verify "$WORK/Penpot.app" && echo "İmza geçerli."
du -sh "$WORK/Penpot.app"

say "DMG oluşturuluyor"
mkdir -p "$WORK/dmg" "$OUTDIR"
mv "$WORK/Penpot.app" "$WORK/dmg/Penpot.app"
ln -s /Applications "$WORK/dmg/Uygulamalar"
rm -f "$DMG"
hdiutil create -volname "Penpot" -srcfolder "$WORK/dmg" -fs APFS -format ULMO -ov "$DMG" >/dev/null
ls -lh "$DMG" | awk '{print $5, $NF}'
shasum -a 256 "$DMG"
