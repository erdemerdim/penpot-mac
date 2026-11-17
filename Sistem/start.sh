#!/usr/bin/env bash
# Penpot'u başlatır: PostgreSQL, Valkey, backend ve frontend.
set -e
L="$(cd "$(dirname "$0")" && pwd)"; cd "$L"
source "$L/penpot.env"
# Bu kuruluma ait süreçleri adres ile ayırt etmek için (başka klasördeki bir Penpot kurulumuna dokunmaz)
LRE="$(printf '%s' "$L" | sed 's/[][\.*^$+?(){}|]/\\&/g')"

# Önceki oturum hâlâ kapanıyorsa (stop.sh çalışıyorsa) bitmesini bekle
LOCK="$L/data/stopping.lock"
for i in $(seq 1 60); do
  [ -f "$LOCK" ] || break
  if ! kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then rm -f "$LOCK"; break; fi  # eski/yarım kalmış kilit
  [ "$i" = 1 ] && echo "Önceki oturum kapanıyor, bekleniyor..."
  sleep 1
done

# Başka bir Penpot (ya da aynı bağlantı noktalarını kullanan bir program) açıksa beklemeden anlaşılır
# bir hata ver. Penpot.app bu dosyayı görünce mesajı pencerede gösterir.
ERRF="$L/logs/baslatma-hatasi.txt"; mkdir -p "$L/logs"; rm -f "$ERRF"
busy() { /usr/sbin/lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }
conflict=""
{ [ -d "$L/data/pg" ] && pg_ctl -D "$L/data/pg" status >/dev/null 2>&1; } || ! busy 5432 || conflict="$conflict 5432"
{ [ -f "$L/data/valkey.pid" ] && kill -0 "$(cat "$L/data/valkey.pid")" 2>/dev/null; } || ! busy 6379 || conflict="$conflict 6379"
pgrep -f "java .*$LRE/patches/macos-tmp\\.clj.*app\\.main" >/dev/null || ! busy 6060 || conflict="$conflict 6060"
pgrep -f "node $LRE/proxy\\.mjs" >/dev/null || ! busy 9001 || conflict="$conflict 9001"
if [ -n "$conflict" ]; then
  echo "Başka bir Penpot açık görünüyor (kullanılan bağlantı noktaları:$conflict). Önce onu kapatın, sonra bu Penpot'u yeniden açın." | tee "$ERRF" >&2
  exit 3
fi

# Veritabanı: ilk kurulumda oluşturulur. Kullanıcı ve veritabanı ayrıca denetlenir, çünkü ilk
# kurulum yarıda kalırsa (uygulama erken kapatılırsa) klasör var ama "penpot" kullanıcısı yok olabilir.
# Denetim tamamlanınca data/pg/.penpot-hazir yazılır; sonraki açılışlar beklemeden başlar.
PGOPTS="-p 5432 -k /tmp -h 127.0.0.1"
if [ ! -d "$L/data/pg" ]; then
  initdb -D "$L/data/pg" -U postgres --auth=trust -E UTF8 --locale=C >/dev/null
fi
if [ ! -f "$L/data/pg/.penpot-hazir" ]; then
  pg_ctl -D "$L/data/pg" status >/dev/null 2>&1 || pg_ctl -D "$L/data/pg" -l "$L/logs/postgres.log" -o "$PGOPTS" -w start >/dev/null
  if [ "$(psql -h 127.0.0.1 -U postgres -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='penpot'")" != 1 ]; then
    psql -h 127.0.0.1 -U postgres -d postgres -c "CREATE USER penpot WITH PASSWORD '${PENPOT_DATABASE_PASSWORD:-penpot}';" >/dev/null
  fi
  if [ "$(psql -h 127.0.0.1 -U postgres -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='penpot'")" != 1 ]; then
    psql -h 127.0.0.1 -U postgres -d postgres -c "CREATE DATABASE penpot OWNER penpot;" >/dev/null
  fi
  touch "$L/data/pg/.penpot-hazir"
else
  # Beklemeden başlat (-W): Java sunucusu açılırken veritabanı da paralel açılır; sunucu
  # veritabanına ilk ~5 sn'de ihtiyaç duymaz, gerekirse bağlanana kadar kendisi bekler.
  pg_ctl -D "$L/data/pg" status >/dev/null 2>&1 || pg_ctl -D "$L/data/pg" -l "$L/logs/postgres.log" -o "$PGOPTS" -W start >/dev/null
fi
echo "PostgreSQL başlatıldı"

if ! valkey-cli -p 6379 ping >/dev/null 2>&1; then
  valkey-server --port 6379 --bind 127.0.0.1 --dir "$L/data" --daemonize yes --logfile "$L/logs/valkey.log" --pidfile "$L/data/valkey.pid"
fi
echo "Valkey çalışıyor"

if ! pgrep -f "java .*$LRE/patches/macos-tmp\\.clj.*app\\.main" >/dev/null; then
  # Java ayarlarını Penpot'un kendi run.sh dosyasından alır (güncellemelerle uyumlu kalsın diye),
  # sonra macOS düzeltmesini (patches/macos-tmp.clj) yükleyerek backend'i başlatır.
  cd "$L/backend"
  OPTS_LINE="$(grep '^export JAVA_OPTS=' run.sh || true)"
  if [ -n "$OPTS_LINE" ]; then
    eval "$OPTS_LINE"
  else
    export JAVA_OPTS="-Djava.util.logging.manager=org.apache.logging.log4j.jul.LogManager -Dlog4j2.configurationFile=log4j2.xml -XX:-OmitStackTraceInFastThrow --sun-misc-unsafe-memory-access=allow --enable-native-access=ALL-UNNAMED --enable-preview $JVM_OPTS $JAVA_OPTS"
  fi
  # Hızlı açılış 1: önceden derlenmiş Penpot kodu (data/penpot-classes.jar, tools/aot-compile.sh üretir).
  # Penpot paketi yalnızca kaynak kodla geliyor; derlenmiş kod olmadan her açılışta tüm kod baştan derlenir.
  # Derlenmiş kod yoksa ya da Penpot güncellendiği için eskidiyse: bu açılış eski yolla yapılır ve
  # derleme arka planda yeniden yapılır, bir sonraki açılış yine hızlı olur.
  CLASSES="$L/data/penpot-classes.jar"
  if [ -f "$CLASSES" ] && [ "$(cat "$L/data/penpot-classes.stamp" 2>/dev/null)" = "$(stat -f "%z-%m" penpot.jar)" ]; then
    MODE=fast; RUN=(-cp "$CLASSES:penpot.jar" clojure.main -i "$L/patches/preload-readers.clj")
  else
    MODE=src; RUN=(-jar penpot.jar)
    nohup bash "$L/tools/aot-compile.sh" </dev/null >"$L/logs/aot-compile.log" 2>&1 &
  fi
  # Hızlı açılış 2: Java AOT önbelleği (JDK 25). İlk çalıştırmada (ya da Penpot/Java güncellenince)
  # önbellek kaydedilir ve Penpot kapanırken yazılır. Önbellek sınıf yoluna bağlı olduğu için iki ayrı dosya.
  AOT="$L/data/penpot-$MODE.aot"
  if [ -f "$AOT" ] && [ "$AOT" -nt penpot.jar ] && [ "$AOT" -nt "$JAVA_HOME/bin/java" ] && { [ $MODE = src ] || [ "$AOT" -nt "$CLASSES" ]; }; then
    AOT_OPT=("-XX:AOTCache=$AOT")
  else
    rm -f "$AOT" "$AOT.config"
    AOT_OPT=("-XX:AOTCacheOutput=$AOT")
  fi
  nohup "$JAVA_HOME/bin/java" "${AOT_OPT[@]}" $JAVA_OPTS "${RUN[@]}" -i "$L/patches/macos-tmp.clj" -m app.main \
    </dev/null >"$L/logs/backend.log" 2>&1 &
  echo $! >"$L/data/backend.pid"
  cd "$L"
fi

# Frontend ayarları
# (Yalnızca gerekirse yazılır: tek parça uygulamada bu dosya paketin içindedir ve değiştirilmemelidir)
CFG="$L/frontend/js/config.js"
if ! grep -qxF "var penpotFlags = \"$PENPOT_FLAGS\";" "$CFG" || ! grep -q "penpotPublicURI" "$CFG"; then
  sed -i '' -e "s|^/*var penpotFlags = .*;|var penpotFlags = \"$PENPOT_FLAGS\";|" "$CFG"
  grep -q "penpotPublicURI" "$CFG" || echo "var penpotPublicURI = \"$PENPOT_PUBLIC_URI\";" >> "$CFG"
fi

if ! pgrep -f "node $LRE/proxy\\.mjs" >/dev/null; then
  nohup node "$L/proxy.mjs" </dev/null >"$L/logs/frontend.log" 2>&1 &
  echo $! >"$L/data/proxy.pid"
fi

# Penpot MCP sunucusu (Claude'un Penpot dosyalarını düzenleyebilmesi için)
if [ -f "$L/mcp/index.js" ] && ! pgrep -f "node $LRE/mcp/index\\.js" >/dev/null; then
  cd "$L/mcp"
  PENPOT_MCP_SERVER_HOST=127.0.0.1 PENPOT_MCP_REPL_ENABLE=false \
    nohup node "$L/mcp/index.js" </dev/null >"$L/logs/mcp.log" 2>&1 &
  echo $! >"$L/data/mcp.pid"
  cd "$L"
fi

# Exporter (PNG/JPG/PDF/SVG/WEBP dışa aktarma), yalnızca bu bilgisayardan erişilebilir
if [ -f "$L/exporter/app.js" ] && ! pgrep -f "node .*$LRE/exporter/app\\.js" >/dev/null; then
  mkdir -p "$L/data/exporter-tmp"
  cd "$L/exporter"
  PENPOT_HTTP_SERVER_PORT=6061 \
    nohup node --import "$L/patches/localhost-only.mjs" "$L/exporter/app.js" </dev/null >"$L/logs/exporter.log" 2>&1 &
  echo $! >"$L/data/exporter.pid"
  cd "$L"
fi

echo -n "Backend başlıyor (ilk açılış 1-2 dk sürebilir)"
for i in $(seq 1 1200); do
  if curl -fs -m 1 http://127.0.0.1:6060/readyz >/dev/null 2>&1 && curl -fs -m 1 -o /dev/null http://127.0.0.1:9001/; then
    echo; echo "Penpot hazır: http://localhost:9001"; exit 0
  fi
  sleep 0.3; [ $((i % 7)) = 0 ] && echo -n "."
done
echo; echo "Backend zamanında açılmadı. Log: $L/logs/backend.log"; exit 1
