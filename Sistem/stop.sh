#!/usr/bin/env bash
# Penpot'u durdurur: MCP, exporter, frontend, backend, Valkey ve PostgreSQL.
# Durdurma sürerken data/stopping.lock dosyası bulunur; start.sh ve Penpot.app bunu görünce bekler.
L="$(cd "$(dirname "$0")" && pwd)"; source "$L/penpot.env"
# Bu kuruluma ait süreçleri adres ile ayırt etmek için (başka klasördeki bir Penpot kurulumuna dokunmaz)
LRE="$(printf '%s' "$L" | sed 's/[][\.*^$+?(){}|]/\\&/g')"
LOCK="$L/data/stopping.lock"
LOG="$L/logs/stop.log"
mkdir -p "$L/data" "$L/logs"
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
T0=$(date +%s)
step() { echo "[$(date '+%H:%M:%S')] +$(( $(date +%s) - T0 ))sn $*" >> "$LOG"; }
step "durdurma başladı"

BACKEND_PATTERN="java .*$LRE/patches/macos-tmp\.clj.*app\.main"
PROXY_PATTERN="node $LRE/proxy\.mjs"

# Önce kibarca kapat (SIGTERM), süre içinde kapanmazsa zorla kapat (varsayılan 10 sn).
stop_pattern() {
  local name="$1" pattern="$2" limit="${3:-10}"
  if ! pkill -TERM -f "$pattern" 2>/dev/null; then step "$name zaten kapalı"; return 0; fi
  for _ in $(seq 1 $((limit * 4))); do
    if ! pgrep -f "$pattern" >/dev/null; then step "$name kapandı"; return 0; fi
    sleep 0.25
  done
  pkill -KILL -f "$pattern" 2>/dev/null
  sleep 1
  step "$name zorla kapatıldı"
}

# MCP sunucusu açık bağlantı varken kapatma sinyalini yok sayıyor; durumsuz olduğu için 1 sn sonra zorla kapat
stop_pattern "MCP" "node $LRE/mcp/index\.js" 1;        rm -f "$L/data/mcp.pid"
stop_pattern "Exporter" "node .*$LRE/exporter/app\.js" 3; rm -f "$L/data/exporter.pid"
stop_pattern "Frontend" "$PROXY_PATTERN" 3
# Backend'e 30 sn ver: ilk kapanışta hızlı açılış önbelleğini (data/penpot.aot) diske yazar
stop_pattern "Backend" "$BACKEND_PATTERN" 30
rm -f "$L/data/proxy.pid" "$L/data/backend.pid"

valkey-cli -p 6379 shutdown nosave >/dev/null 2>&1 && step "Valkey kapandı" || step "Valkey zaten kapalı"
pg_ctl -D "$L/data/pg" -m fast -w -t 20 stop >/dev/null 2>&1 && step "PostgreSQL kapandı" || step "PostgreSQL zaten kapalı"
step "durdurma bitti"
echo "Penpot durduruldu"
