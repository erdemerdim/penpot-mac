#!/usr/bin/env bash
# Penpot backend'ini önceden derler (Clojure AOT) ve data/penpot-classes.jar olarak kaydeder.
# Penpot paketi yalnızca kaynak kodla geliyor; derlenmiş sınıflar olmadan her açılışta tüm kod
# baştan derlenir (~4-5 sn). Sonuç data/penpot-classes.jar; start.sh varsa onu kullanır.
# Penpot güncellenince start.sh bunu kendiliğinden arka planda yeniden çalıştırır.
set -eo pipefail
L="$(cd "$(dirname "$0")/.." && pwd)"
source "$L/penpot.env"
OUT="$L/data/clj-classes"; TMP="$L/data/clj-classes.tmp"
rm -rf "$TMP"; mkdir -p "$TMP"
cd "$L/backend"
eval "$(grep '^export JAVA_OPTS=' run.sh)"
# app.main ve bağlı olduğu tüm ad alanları derlenir; sunucu başlatılmaz (yalnızca derleme)
"$JAVA_HOME/bin/java" $JAVA_OPTS -Dclojure.compile.path="$TMP" -cp "$TMP:penpot.jar" clojure.main \
  -e "(binding [*compile-path* \"$TMP\"] (compile 'app.main)) (shutdown-agents) (System/exit 0)"
# Java açılış önbelleği (AOT cache) sınıf yolunda klasör kabul etmiyor: derlenmiş sınıfları jar'a paketle
"$JAVA_HOME/bin/jar" --create --file "$L/data/penpot-classes.jar.tmp" -C "$TMP" .
mv "$L/data/penpot-classes.jar.tmp" "$L/data/penpot-classes.jar"
# Hangi penpot.jar için derlendiği (boyut-değişiklik zamanı); start.sh bununla eşleştirir
stat -f "%z-%m" "$L/backend/penpot.jar" > "$L/data/penpot-classes.stamp"
rm -rf "$TMP" "$OUT"
rm -f "$L/data/penpot-fast.aot" "$L/data/penpot.aot"   # sınıf yolu değişti: Java açılış önbelleği yeniden oluşturulsun
echo "Derlendi: $(du -h "$L/data/penpot-classes.jar" | cut -f1) (data/penpot-classes.jar)"
