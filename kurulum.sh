#!/usr/bin/env bash
# Penpot'u (Docker'sız) bu Mac'e kurar. Apple Silicon (M1/M2/M3/M4...) Mac gerekir.
#
#   ./kurulum.sh              -> eksik olan her şeyi indirir/derler, Penpot.app'i hazırlar ve dener
#   ./kurulum.sh --guncelle   -> yalnızca sürümü değişen bileşenleri yeniler ve uygulamaları derler
#                               (Penpot Güncelle bunu depodan çekilen değişikliklerden sonra kullanır)
#
# İndirilenler/derlenenler (Sistem/ altına, depoya girmez):
#   jdk (Azul Zulu), node, pgsql (kaynaktan), valkey (kaynaktan), backend/frontend/exporter/mcp
#   (Penpot'un resmî Docker imajlarından, Docker olmadan), browsers (dışa aktarma için Chromium),
#   bin/magick ve bin/pdfunite (tools/*.swift'ten derlenir).
# Sürümler: Sistem/surumler.env
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
L="$ROOT/Sistem"
MODE="${1:-}"
source "$L/surumler.env"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf '\n\033[31mHATA: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- ön koşullar
[ "$(uname -s)" = Darwin ] || die "Bu kurulum yalnızca macOS içindir."
[ "$(uname -m)" = arm64 ] || die "Bu kurulum Apple Silicon (arm64) Mac içindir."
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swiftc >/dev/null 2>&1 || ! command -v make >/dev/null 2>&1; then
  xcode-select --install 2>/dev/null || true
  die "Xcode Komut Satırı Araçları gerekli. Açılan pencereden kurun, bitince bu betiği yeniden çalıştırın."
fi
for c in curl shasum python3 tar git osacompile codesign; do command -v "$c" >/dev/null || die "$c bulunamadı."; done

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
NCPU="$(sysctl -n hw.ncpu)"

# İndirir ve SHA-256 ile doğrular: dl <url> <sha256> <hedef dosya>
dl() {
  curl -fL --retry 3 --progress-bar -o "$3" "$1" || die "İndirilemedi: $1"
  [ "$(shasum -a 256 "$3" | cut -d' ' -f1)" = "$2" ] || die "Doğrulama başarısız (dosya bozuk ya da değişmiş): $1"
}
# Bileşen sürüm damgası: kurulu sürüm surumler.env'dekiyle aynıysa yeniden kurulmaz
stamp_ok() { [ -f "$L/$1/.kurulum-surumu" ] && [ "$(cat "$L/$1/.kurulum-surumu")" = "$2" ]; }
stamp()    { echo "$2" > "$L/$1/.kurulum-surumu"; }

mkdir -p "$L/data" "$L/logs" "$L/bin"

# ---------------------------------------------------------------- Java
if ! stamp_ok jdk "$JDK_URL"; then
  say "Java indiriliyor (Azul Zulu)"
  dl "$JDK_URL" "$JDK_SHA256" "$TMP/jdk.tgz"
  mkdir -p "$TMP/jdk"; tar -xzf "$TMP/jdk.tgz" -C "$TMP/jdk"
  H="$(find "$TMP/jdk" -maxdepth 4 -type d -path '*/Contents/Home' | head -1)"
  [ -n "$H" ] && [ -x "$H/bin/java" ] || die "Java paketi beklenen yapıda değil."
  J="$(dirname "$(dirname "$H")")"
  rm -rf "$L/jdk"; mv "$J" "$L/jdk"; stamp jdk "$JDK_URL"
  info "$("$L/jdk/Contents/Home/bin/java" -version 2>&1 | head -1)"
fi

# ---------------------------------------------------------------- Node.js
if ! stamp_ok node "$NODE_VERSION"; then
  say "Node.js $NODE_VERSION indiriliyor"
  dl "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-darwin-arm64.tar.xz" "$NODE_SHA256" "$TMP/node.txz"
  tar -xJf "$TMP/node.txz" -C "$TMP"
  rm -rf "$L/node"; mv "$TMP/node-v$NODE_VERSION-darwin-arm64" "$L/node"; stamp node "$NODE_VERSION"
fi
export PATH="$L/node/bin:$PATH"

# ---------------------------------------------------------------- PostgreSQL
# Derlenen programlar kütüphanelerini kendi klasörlerine göre (@rpath) bulur; klasör taşınabilir.
pg_relocatable() {
  local P="$1" f lib
  for f in "$P"/lib/*.dylib; do
    [ -L "$f" ] && continue
    install_name_tool -id "@rpath/$(basename "$f")" "$f" 2>/dev/null || true
  done
  for f in "$P"/bin/* "$P"/lib/*.dylib "$P"/lib/*.so; do
    [ -L "$f" ] && continue
    file "$f" | grep -q Mach-O || continue
    for lib in $(otool -L "$f" | awk 'NR>1{print $1}' | grep "^$P/lib/" || true); do
      install_name_tool -change "$lib" "@rpath/$(basename "$lib")" "$f" 2>/dev/null || true
    done
    case "$f" in
      */bin/*) install_name_tool -add_rpath @executable_path/../lib "$f" 2>/dev/null || true ;;
      *)       install_name_tool -add_rpath @loader_path "$f" 2>/dev/null || true ;;
    esac
    codesign -f -s - "$f" 2>/dev/null
  done
}
if ! stamp_ok pgsql "$PG_VERSION"; then
  [ -d "$L/data/pg" ] && [ "$(cat "$L/data/pg/PG_VERSION")" != "${PG_VERSION%%.*}" ] \
    && die "Mevcut veritabanı PostgreSQL $(cat "$L/data/pg/PG_VERSION") ile oluşturulmuş; ${PG_VERSION%%.*} sürümüne otomatik geçiş yapılmaz."
  say "PostgreSQL $PG_VERSION derleniyor (birkaç dakika sürer)"
  dl "https://ftp.postgresql.org/pub/source/v$PG_VERSION/postgresql-$PG_VERSION.tar.bz2" "$PG_SHA256" "$TMP/pg.tbz"
  tar -xjf "$TMP/pg.tbz" -C "$TMP"
  PREFIX="$TMP/pgsql"
  ( cd "$TMP/postgresql-$PG_VERSION"
    ./configure --prefix="$PREFIX" --without-icu --without-readline --with-uuid=e2fs >"$TMP/pg-configure.log" 2>&1 \
      || { tail -30 "$TMP/pg-configure.log"; exit 1; }
    make -j"$NCPU" >"$TMP/pg-make.log" 2>&1 || { tail -30 "$TMP/pg-make.log"; exit 1; }
    make install >/dev/null && make -C contrib -j"$NCPU" install >/dev/null
  ) || die "PostgreSQL derlenemedi."
  pg_relocatable "$PREFIX"
  rm -rf "$L/pgsql"; mv "$PREFIX" "$L/pgsql"; stamp pgsql "$PG_VERSION"
  "$L/pgsql/bin/psql" --version >/dev/null || die "PostgreSQL derlendi ama çalışmıyor."
fi

# ---------------------------------------------------------------- Valkey
if ! stamp_ok valkey "$VALKEY_VERSION"; then
  say "Valkey $VALKEY_VERSION derleniyor"
  dl "https://github.com/valkey-io/valkey/archive/refs/tags/$VALKEY_VERSION.tar.gz" "$VALKEY_SHA256" "$TMP/valkey.tgz"
  tar -xzf "$TMP/valkey.tgz" -C "$TMP"
  ( cd "$TMP/valkey-$VALKEY_VERSION"
    make -j"$NCPU" MALLOC=libc BUILD_TLS=no >"$TMP/valkey-make.log" 2>&1 || { tail -30 "$TMP/valkey-make.log"; exit 1; }
    make PREFIX="$TMP/valkey" install >/dev/null
  ) || die "Valkey derlenemedi."
  rm -rf "$L/valkey"; mv "$TMP/valkey" "$L/valkey"; stamp valkey "$VALKEY_VERSION"
fi

# ---------------------------------------------------------------- Penpot
if [ ! -f "$L/backend/penpot.jar" ] || [ ! -f "$L/frontend/index.html" ]; then
  say "Penpot $PENPOT_VERSION indiriliyor (backend, frontend, exporter, MCP)"
  for img in backend frontend exporter mcp; do
    info "$img"
    "$L/tools/pull_image.sh" "penpotapp/$img" "$PENPOT_VERSION" "$TMP/$img-img" 2>/dev/null || die "penpotapp/$img:$PENPOT_VERSION indirilemedi."
  done
  [ -f "$TMP/backend-img/opt/penpot/backend/penpot.jar" ] && [ -f "$TMP/frontend-img/var/www/app/index.html" ] \
    && [ -f "$TMP/exporter-img/opt/penpot/exporter/app.js" ] && [ -f "$TMP/mcp-img/opt/penpot/mcp/index.js" ] \
    || die "Penpot dosyaları beklenen yerde değil."
  rm -rf "$L/backend" "$L/frontend" "$L/exporter" "$L/mcp"
  mv "$TMP/backend-img/opt/penpot/backend" "$L/backend"
  mv "$TMP/frontend-img/var/www/app" "$L/frontend"
  mv "$TMP/exporter-img/opt/penpot/exporter" "$L/exporter"
  mv "$TMP/mcp-img/opt/penpot/mcp" "$L/mcp"
  rm -rf "$TMP"/*-img
fi
if [ ! -d "$L/mcp/node_modules/.pnpm" ] || ! (cd "$L/mcp" && node -e 'import("sharp").then(()=>0,()=>process.exit(1))') 2>/dev/null; then
  say "MCP görsel kütüphanesi (sharp) macOS için hazırlanıyor"
  "$L/tools/mcp-sharp-macos.sh" "$L/mcp" | sed 's/^/    /'
fi
if [ -z "$(ls -d "$L"/browsers/chromium_headless_shell-* 2>/dev/null)" ]; then
  say "Dışa aktarma için Chromium indiriliyor"
  (cd "$L/exporter" && PLAYWRIGHT_BROWSERS_PATH="$L/browsers" node node_modules/playwright/cli.js install --only-shell chromium) \
    || die "Chromium indirilemedi."
fi

# ---------------------------------------------------------------- yardımcı araçlar
for t in magick pdfunite; do
  if [ ! -x "$L/bin/$t" ] || [ "$L/tools/$t.swift" -nt "$L/bin/$t" ]; then
    say "bin/$t derleniyor"
    swiftc -O "$L/tools/$t.swift" -o "$L/bin/$t"
  fi
done
chmod +x "$L/bin/convert" "$L"/*.sh "$L"/tools/*.sh "$L"/tools/app/*.sh "$ROOT"/*.sh

# ---------------------------------------------------------------- ayarlar ve gizli değerler
if [ ! -f "$L/penpot.env" ]; then
  say "Ayar dosyası (penpot.env) oluşturuluyor, gizli değerler yeni üretiliyor"
  SECRET="$(openssl rand -hex 32)"; DBPW="$(openssl rand -hex 16)"
  sed -e "s/__SECRET_KEY__/$SECRET/" -e "s/__DB_PASSWORD__/$DBPW/" "$L/penpot.env.example" > "$L/penpot.env"
  chmod 600 "$L/penpot.env"
fi

# ---------------------------------------------------------------- hızlı açılış derlemesi
if [ ! -f "$L/data/penpot-classes.jar" ] || [ "$(cat "$L/data/penpot-classes.stamp" 2>/dev/null)" != "$(stat -f "%z-%m" "$L/backend/penpot.jar")" ]; then
  say "Penpot sunucusu önceden derleniyor (hızlı açılış için, 1-2 dk)"
  bash "$L/tools/aot-compile.sh" >"$L/logs/aot-compile.log" 2>&1 || die "Derleme başarısız. Ayrıntılar: Sistem/logs/aot-compile.log"
  info "$(tail -1 "$L/logs/aot-compile.log")"
fi

# ---------------------------------------------------------------- uygulamalar
say "Penpot.app ve Penpot Güncelle.app derleniyor"
bash "$L/tools/app/build-all.sh" "$ROOT" | sed 's/^/    /'

if [ "$MODE" = "--guncelle" ]; then say "Güncelleme tamam."; exit 0; fi

# ---------------------------------------------------------------- deneme açılışı
say "Penpot ilk kez başlatılıyor (veritabanı oluşturulur, 1-2 dk sürebilir)"
if bash "$L/start.sh"; then
  say "Deneme bitti, Penpot durduruluyor (açılış önbelleği yazılıyor)"
  bash "$L/stop.sh" >/dev/null
else
  bash "$L/stop.sh" >/dev/null || true
  die "Penpot açılmadı. Ayrıntılar: Sistem/logs/backend.log"
fi

cat <<EOF

Kurulum tamam.
  Açmak için:  $ROOT/Penpot.app   (Finder'da çift tıklayın)

İlk açılışta macOS sorabilir:
  - "Penpot, Belgeler klasörünüzdeki dosyalara erişmek istiyor" -> İzin Ver.
    (Uygulama her yeniden derlendiğinde bu soru bir kez daha gelebilir; normaldir.)
  - Uygulama açılmazsa: Sistem Ayarları -> Gizlilik ve Güvenlik -> "Yine de Aç".
Hesap: Penpot ekranında "Hesap oluştur" ile yeni bir hesap açın (bu Mac'e özeldir).
EOF
