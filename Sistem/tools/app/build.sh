#!/usr/bin/env bash
# Penpot.app'i derler: Sistem/tools/app/build.sh <çıktı .app yolu> <ikon .icns>
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:?çıktı .app yolu gerekli}"
ICON="${2:?ikon dosyası gerekli}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
APP="$TMP/Penpot.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -target arm64-apple-macos13.0 -framework AppKit -framework WebKit \
  "$HERE/PenpotApp.swift" -o "$APP/Contents/MacOS/Penpot"
cp "$ICON" "$APP/Contents/Resources/Penpot.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Penpot</string>
  <key>CFBundleDisplayName</key><string>Penpot</string>
  <key>CFBundleIdentifier</key><string>local.penpot.desktop</string>
  <key>CFBundleExecutable</key><string>Penpot</string>
  <key>CFBundleIconFile</key><string>Penpot</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
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
codesign -f -s - "$APP" >/dev/null 2>&1
rm -rf "$OUT"; mv "$APP" "$OUT"; touch "$OUT"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$OUT"
echo "Derlendi: $OUT"
