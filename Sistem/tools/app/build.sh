#!/usr/bin/env bash
# Penpot.app'i derler: Sistem/tools/app/build.sh <çıktı .app yolu> <ikon .icns>
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:?çıktı .app yolu gerekli}"
ICON="${2:?ikon dosyası gerekli}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
APP="$TMP/Penpot.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Birden fazla Swift dosyasında giriş noktası main.swift adlı dosya olmalı
cp "$HERE/PenpotApp.swift" "$TMP/main.swift"
swiftc -O -target arm64-apple-macos13.0 -framework AppKit -framework WebKit \
  "$TMP/main.swift" "$HERE/Guncelleme.swift" -o "$APP/Contents/MacOS/Penpot"
cp "$ICON" "$APP/Contents/Resources/Penpot.icns"
# Tek parça (DMG) sürümü ayrı bir kimlik kullanır: PENPOT_BUNDLE_ID, PENPOT_APP_VERSION
BUNDLE_ID="${PENPOT_BUNDLE_ID:-local.penpot.desktop}"; APP_VERSION="${PENPOT_APP_VERSION:-1.0}"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Penpot</string>
  <key>CFBundleDisplayName</key><string>Penpot</string>
  <key>CFBundleIdentifier</key><string>__BUNDLE_ID__</string>
  <key>CFBundleExecutable</key><string>Penpot</string>
  <key>CFBundleIconFile</key><string>Penpot</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>__VERSION__</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.graphics-design</string>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsLocalNetworking</key><true/></dict>
  <key>NSHumanReadableCopyright</key><string>Penpot (MPL-2.0), yerel kurulum</string>
</dict>
</plist>
PLIST
sed -i '' -e "s/__BUNDLE_ID__/$BUNDLE_ID/" -e "s/__VERSION__/$APP_VERSION/" "$APP/Contents/Info.plist"
# DMG sürümü: içindeki Penpot sürümü ve güncelleme denetiminin soracağı GitHub deposu (Guncelleme.swift)
PB=/usr/libexec/PlistBuddy
[ -n "${PENPOT_VERSION_INFO:-}" ] && $PB -c "Add :PenpotVersion string $PENPOT_VERSION_INFO" "$APP/Contents/Info.plist"
[ -n "${PENPOT_UPDATE_REPO:-}" ] && $PB -c "Add :PenpotUpdateRepo string $PENPOT_UPDATE_REPO" "$APP/Contents/Info.plist"
codesign -f -s - "$APP" >/dev/null 2>&1
rm -rf "$OUT"; mv "$APP" "$OUT"; touch "$OUT"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$OUT"
echo "Derlendi: $OUT"
