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

# İlk kurulumda veritabanını hazırla
if [ ! -d "$L/data/pg" ]; then
  initdb -D "$L/data/pg" -U postgres --auth=trust -E UTF8 --locale=C >/dev/null
  pg_ctl -D "$L/data/pg" -l "$L/logs/postgres.log" -o "-p 5432 -k /tmp -h 127.0.0.1" -w start >/dev/null
  psql -h 127.0.0.1 -U postgres -c "CREATE USER penpot WITH PASSWORD '${PENPOT_DATABASE_PASSWORD:-penpot}';" >/dev/null
  psql -h 127.0.0.1 -U postgres -c "CREATE DATABASE penpot OWNER penpot;" >/dev/null
else
  # Beklemeden başlat (-W): Java sunucusu açılırken veritabanı da paralel açılır; sunucu
  # veritabanına ilk ~5 sn'de ihtiyaç duymaz, gerekirse bağlanana kadar kendisi bekler.
  pg_ctl -D "$L/data/pg" status >/dev/null 2>&1 || pg_ctl -D "$L/data/pg" -l "$L/logs/postgres.log" -o "-p 5432 -k /tmp -h 127.0.0.1" -W start >/dev/null
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
    AOT_OPT="-XX:AOTCache=$AOT"
  else
    rm -f "$AOT" "$AOT.config"
    AOT_OPT="-XX:AOTCacheOutput=$AOT"
  fi
  nohup "$JAVA_HOME/bin/java" $AOT_OPT $JAVA_OPTS "${RUN[@]}" -i "$L/patches/macos-tmp.clj" -m app.main \
    </dev/null >"$L/logs/backend.log" 2>&1 &
  echo $! >"$L/data/backend.pid"
  cd "$L"
fi

# Frontend ayarları
sed -i '' -e "s|^/*var penpotFlags = .*;|var penpotFlags = \"$PENPOT_FLAGS\";|" "$L/frontend/js/config.js"
grep -q "penpotPublicURI" "$L/frontend/js/config.js" || echo "var penpotPublicURI = \"$PENPOT_PUBLIC_URI\";" >> "$L/frontend/js/config.js"

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
