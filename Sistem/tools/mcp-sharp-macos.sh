#!/usr/bin/env bash
# Penpot MCP sunucusunun görsel kütüphanesi (sharp) Docker imajında yalnızca Linux için gelir.
# Bu betik, kurulu sharp sürümünün istediği macOS (arm64) paketlerini npm'den indirir,
# bütünlüğünü doğrular ve sharp'ın bulabileceği yere bağlar.
# Kullanım: mcp-sharp-macos.sh <mcp klasörü>
set -euo pipefail
MCP="${1:?mcp klasörü gerekli}"
P="$MCP/node_modules/.pnpm"

SHARP_DIR="$(ls -d "$P"/sharp@*/node_modules/sharp 2>/dev/null | head -1)"
[ -n "$SHARP_DIR" ] || { echo "sharp bulunamadı: $P" >&2; exit 1; }
SHARP_NM="$(dirname "$SHARP_DIR")"   # .../sharp@x_.../node_modules

# sharp'ın macOS için istediği paket adları ve sürümleri
DEPS="$(python3 -I - "$SHARP_DIR/package.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for k, v in d.get("optionalDependencies", {}).items():
    if k in ("@img/sharp-darwin-arm64", "@img/sharp-libvips-darwin-arm64"):
        print(k, v)
PY
)"
[ -n "$DEPS" ] || { echo "sharp macOS paketleri tanımlı değil" >&2; exit 1; }

TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT
# Göreli sembolik bağlantı: klasör taşınsa da bağlantılar çalışmaya devam eder
rel_link() { ln -sfn "$(python3 -I -c 'import os,sys;print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$1" "$(dirname "$2")")" "$2"; }
while read -r name ver; do
  base="${name#@img/}"
  dir="$P/@img+$base@$ver/node_modules/@img/$base"
  if [ ! -f "$dir/package.json" ]; then
    meta="$(curl -fsSL "https://registry.npmjs.org/$name/$ver")"
    url="$(printf '%s' "$meta" | python3 -I -c 'import sys,json;print(json.load(sys.stdin)["dist"]["tarball"])')"
    integ="$(printf '%s' "$meta" | python3 -I -c 'import sys,json;print(json.load(sys.stdin)["dist"]["integrity"])')"
    curl -fsSL "$url" -o "$TMPD/pkg.tgz"
    calc="sha512-$(openssl dgst -sha512 -binary "$TMPD/pkg.tgz" | base64)"
    [ "$calc" = "$integ" ] || { echo "$name bütünlük doğrulaması başarısız" >&2; exit 1; }
    mkdir -p "$dir"
    tar -xzf "$TMPD/pkg.tgz" -C "$dir" --strip-components=1
    rm -f "$TMPD/pkg.tgz"
  fi
  mkdir -p "$SHARP_NM/@img"
  rel_link "$dir" "$SHARP_NM/@img/$base"
  echo "$name $ver hazır"
done <<< "$DEPS"

# libvips'i macOS sharp paketinin yanına da bağla
DARWIN="$(ls -d "$P"/@img+sharp-darwin-arm64@*/node_modules/@img 2>/dev/null | head -1)"
VIPS="$(ls -d "$P"/@img+sharp-libvips-darwin-arm64@*/node_modules/@img/sharp-libvips-darwin-arm64 2>/dev/null | head -1)"
[ -n "$DARWIN" ] && [ -n "$VIPS" ] && rel_link "$VIPS" "$DARWIN/sharp-libvips-darwin-arm64"

cd "$MCP" && node -e 'import("sharp").then(m=>console.log("sharp çalışıyor, libvips " + m.default.versions.vips)).catch(e=>{console.error("sharp yüklenemedi: " + e.message); process.exit(1)})'
