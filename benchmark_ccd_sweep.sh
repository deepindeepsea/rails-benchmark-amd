#!/bin/bash
# benchmark_ccd_sweep.sh
#
# Sweep Puma across N server CCDs and capture full AMD PMC pipeline metrics
# per run. Reserves CCD 9 (cores 88-95) as a dedicated wrk client CCD.
# wrk threads scale 1:1 with server CCDs (up to 8 threads = saturates client CCD).
#
# Usage:
#   ./benchmark_ccd_sweep.sh                  # default sweep: 1 2 4 8 11
#   ./benchmark_ccd_sweep.sh "1 2 3 4"       # custom CCD counts
#   DURATION=60 CONNS_PER_THREAD=200 ./benchmark_ccd_sweep.sh
#
# Outputs per run:
#   rails_ccd<N>_wrk<W>_<timestamp>.html        (next to this script)
#   plus the toolkit's own console pipeline summary

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_DIR="${TOOLKIT_DIR:-/home/amd/pradeepn/amd-perf-toolkit}"
PIPE="$TOOLKIT_DIR/amd_pipeline_metrics.sh"

CCD_LIST="${*:-1 2 4 8 11}"
DURATION="${DURATION:-30}"
CONNS_PER_THREAD="${CONNS_PER_THREAD:-100}"
APP_URL="${APP_URL:-http://localhost:3000/hello}"

# One folder per sweep — keeps working dir clean and groups related runs
SWEEP_TS=$(date +%Y%m%d_%H%M%S)
SWEEP_DIR="${SWEEP_DIR:-$SCRIPT_DIR/results/sweep_${SWEEP_TS}}"
mkdir -p "$SWEEP_DIR"
SWEEP_LOG="$SWEEP_DIR/sweep.log"
exec > >(tee -a "$SWEEP_LOG") 2>&1

# Physical CCD layout on EPYC 9684X (matches benchmark_ccd_pinned.sh)
CCD_GROUPS=( "0 7" "8 15" "16 23" "24 31" "32 39" "40 47" \
             "48 55" "56 63" "64 71" "72 79" "80 87" "88 95" )
CLIENT_CCD_IDX=11  # CCD 9 in die_id, but last entry in physical-order list
read -r CLIENT_FIRST CLIENT_LAST <<< "${CCD_GROUPS[$CLIENT_CCD_IDX]}"

echo "=== CCD Sweep Configuration ==="
echo "Server CCD counts: $CCD_LIST"
echo "Client CCD:        cores $CLIENT_FIRST-$CLIENT_LAST (reserved)"
echo "Duration:          ${DURATION}s per run"
echo "Conns/thread:      $CONNS_PER_THREAD"
echo "Results dir:       $SWEEP_DIR"
echo ""

for N in $CCD_LIST; do
    if [ "$N" -gt "$CLIENT_CCD_IDX" ]; then
        echo "[skip] N=$N exceeds available server CCDs ($CLIENT_CCD_IDX reserved for client)"
        continue
    fi

    # Build server core list from first N CCDs
    SERVER_CORES=""
    for i in $(seq 0 $((N - 1))); do
        read -r f l <<< "${CCD_GROUPS[$i]}"
        [ -z "$SERVER_CORES" ] && SERVER_CORES="$f-$l" || SERVER_CORES="$SERVER_CORES,$f-$l"
    done
    WORKERS=$((N * 8))

    # wrk threads = N (capped at 8 = client CCD size)
    WRK_T=$N
    [ "$WRK_T" -gt 8 ] && WRK_T=8
    WRK_FIRST=$CLIENT_FIRST
    WRK_LAST=$((CLIENT_FIRST + WRK_T - 1))
    WRK_CORES="$WRK_FIRST-$WRK_LAST"
    WRK_CONNS=$((WRK_T * CONNS_PER_THREAD))

    HTML="$SWEEP_DIR/rails_ccd${N}_wrk${WRK_T}.html"

    echo ""
    echo "============================================================"
    echo "  Run: N=$N CCDs | Puma workers=$WORKERS on cores $SERVER_CORES"
    echo "  wrk: -t$WRK_T -c$WRK_CONNS pinned to cores $WRK_CORES"
    echo "  HTML: $HTML"
    echo "============================================================"

    # Kill any leftover puma
    pkill -f puma 2>/dev/null || true
    sleep 2

    # Start Puma on server cores
    cd "$SCRIPT_DIR"
    export RAILS_ENV=production
    export SECRET_KEY_BASE=$(bundle exec rails secret 2>/dev/null)
    export WEB_CONCURRENCY=$WORKERS
    export RAILS_MAX_THREADS=1

    taskset -c "$SERVER_CORES" bundle exec puma -e production -p 3000 \
        > /tmp/puma_ccd${N}.log 2>&1 &
    PUMA_PID=$!

    # Wait for Puma to be ready
    for i in $(seq 1 60); do
        curl -s http://localhost:3000/health > /dev/null 2>&1 && break
        sleep 1
    done

    # Build PERF_CPULIST = server cores only (exclude client CCD)
    PERF_CPULIST="$SERVER_CORES" \
    HTML_OUT="$HTML" \
        bash "$PIPE" "taskset -c $WRK_CORES wrk -t$WRK_T -c$WRK_CONNS -d${DURATION}s --latency $APP_URL"

    # Tear down Puma
    kill $PUMA_PID 2>/dev/null || pkill -f puma
    sleep 3

    echo "[done] N=$N -> $(basename $HTML)"
done

echo ""
echo "=== Sweep complete ==="
echo "All artifacts saved under: $SWEEP_DIR"
ls -1 "$SWEEP_DIR"/ 2>/dev/null
