#!/bin/bash

# benchmark_ccd_pinned.sh
# Run Rails benchmark with Puma workers pinned to specific CCDs.
#
# Strategy: allocate 7 server cores per CCD, pin wrk client to the last core.
# This keeps all traffic within known L3 cache domains and avoids cross-CCD noise.
#
# Usage:
#   ./benchmark_ccd_pinned.sh            # single CCD (cores 0-6, client on 7)
#   ./benchmark_ccd_pinned.sh all        # all 12 CCDs (84 workers, client on 95)
#   ./benchmark_ccd_pinned.sh <n>        # first N CCDs
#
# AMD EPYC 9684X CCD layout (verified via sysfs die_id):
#   CCD  0: cores  0-7    CCD  4: cores  8-15
#   CCD  8: cores 16-23   CCD  2: cores 24-31
#   CCD  6: cores 32-39   CCD 10: cores 40-47
#   CCD  3: cores 48-55   CCD  7: cores 56-63
#   CCD 11: cores 64-71   CCD  1: cores 72-79
#   CCD  5: cores 80-87   CCD  9: cores 88-95

set -e

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:-1}"
DURATION="${2:-30}"
CONNECTIONS="${3:-100}"
APP_URL="http://localhost:3000"

# CCD groups in physical order (8 cores each, sequential in core numbers)
# Format: "first_core last_core"
CCD_GROUPS=(
    "0 7"
    "8 15"
    "16 23"
    "24 31"
    "32 39"
    "40 47"
    "48 55"
    "56 63"
    "64 71"
    "72 79"
    "80 87"
    "88 95"
)
TOTAL_CCDS=${#CCD_GROUPS[@]}

# Determine how many CCDs to use
if [[ "$MODE" == "all" ]]; then
    NUM_CCDS=$TOTAL_CCDS
elif [[ "$MODE" =~ ^[0-9]+$ ]] && [[ "$MODE" -le "$TOTAL_CCDS" ]]; then
    NUM_CCDS=$MODE
else
    echo "Usage: $0 [1-12|all] [duration_seconds] [connections]"
    exit 1
fi

# Build taskset CPU list:
#   CCDs 0..(N-2): all 8 cores for server
#   Last CCD:      7 cores for server, last core for client
SERVER_CORES=""
for i in $(seq 0 $((NUM_CCDS - 1))); do
    read -r first last <<< "${CCD_GROUPS[$i]}"
    if [[ $i -lt $((NUM_CCDS - 1)) ]]; then
        # Full CCD — all 8 cores to server
        range="${first}-${last}"
    else
        # Last CCD — reserve last core for client
        range="${first}-$((last - 1))"
    fi
    if [[ -z "$SERVER_CORES" ]]; then
        SERVER_CORES="$range"
    else
        SERVER_CORES="${SERVER_CORES},${range}"
    fi
done

# Client core: last core of the last used CCD only
read -r _ CLIENT_CORE <<< "${CCD_GROUPS[$((NUM_CCDS - 1))]}"

# Workers: 8 per CCD for all but last, 7 for last CCD
WORKERS=$(( (NUM_CCDS - 1) * 8 + 7 ))

echo "=== CCD-Pinned Rails Benchmark ==="
echo "CCDs used:       $NUM_CCDS / $TOTAL_CCDS"
echo "Server cores:    $SERVER_CORES"
echo "Client core:     $CLIENT_CORE"
echo "Puma workers:    $WORKERS (8 per CCD except last, which gives 1 core to client)"
echo "Threads/worker:  1 (CPU-bound workload)"
echo "Connections:     $CONNECTIONS"
echo "Duration:        ${DURATION}s"
echo ""

# Stop any running Puma
pkill -f puma 2>/dev/null || true
sleep 2

# Start Puma pinned to server cores
cd "$APP_DIR"
export RAILS_ENV=production
export SECRET_KEY_BASE=$(bundle exec rails secret)
export WEB_CONCURRENCY=$WORKERS
export RAILS_MAX_THREADS=1

echo "Starting Puma with $WORKERS workers pinned to cores: $SERVER_CORES"
taskset -c "$SERVER_CORES" bundle exec puma -e production -p 3000 &
PUMA_PID=$!

# Wait for Puma to be ready
echo "Waiting for Puma to boot..."
for i in $(seq 1 30); do
    if curl -s "$APP_URL/health" > /dev/null 2>&1; then
        echo "Puma is ready."
        break
    fi
    sleep 1
done

echo ""
echo "Running wrk on core $CLIENT_CORE..."
taskset -c "$CLIENT_CORE" wrk -t1 -c"$CONNECTIONS" -d"${DURATION}s" --latency "$APP_URL/hello"

echo ""
echo "Benchmark complete. Stopping Puma (PID $PUMA_PID)..."
kill $PUMA_PID 2>/dev/null || pkill -f puma
