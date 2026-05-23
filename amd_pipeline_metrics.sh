#!/bin/bash

# AMD Pipeline Metrics Analysis
# Displays human-readable metrics like PerfSpect
# Parses raw events and calculates derived metrics

WORKLOAD="${1:-sleep 2}"
DURATION="${2:-2}"

# ─── Script directory (so we can find amd_cpu_placement.py) ────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── CPU info (deduplicated model name) ────────────────────────────────────────
CPU_MODEL=$(lscpu | grep 'Model name' | head -1 | cut -d: -f2 | xargs | sed 's/  */ /g')
TOTAL_CORES=$(nproc)

echo "=== AMD Performance Analysis ==="
echo "CPU:          $CPU_MODEL"
echo "Total Cores:  $TOTAL_CORES"
echo "Workload:     $WORKLOAD"
echo ""

# ─── Collect all events in one perf stat call (more efficient) ─────────────────
# Also captures metric-value (e.g. "CPUs utilized" from task-clock)
collect_group() {
    local events="$1"
    local workload="$2"

    perf stat -j -e "$events" -- $workload 2>&1 \
        | grep '"event"' \
        | python3 -c "
import sys, json
results = {}
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
        event = obj.get('event', '').strip()
        val   = obj.get('counter-value', '0').replace(',','').strip()
        mval  = obj.get('metric-value', '')
        munit = obj.get('metric-unit', '')
        results[event] = float(val) if val and val not in ['<not counted>', '<not supported>'] else 0.0
        # Store metric-value if present (e.g. CPUs utilized from task-clock)
        if mval and mval not in ['<not counted>', '<not supported>', '']:
            try:
                results[event + '__metric'] = float(str(mval).replace(',',''))
                results[event + '__unit']   = 0.0  # placeholder to signal unit exists
            except:
                pass
    except:
        pass
for k, v in results.items():
    print(f'{k}={v}')
" 2>/dev/null
}

# ─── Parse key=value output into bash associative array ───────────────────────
declare -A E  # E[event_name] = counter_value

load_events() {
    local raw_output="$1"
    while IFS='=' read -r key val; do
        E["$key"]="$val"
    done <<< "$raw_output"
}

# ─── Arithmetic helper ─────────────────────────────────────────────────────────
calc() {
    python3 -c "
import sys
try:
    result = eval('$1')
    if isinstance(result, float):
        print(f'{result:.2f}')
    else:
        print(result)
except ZeroDivisionError:
    print('N/A')
except:
    print('N/A')
"
}

calcf() {
    # Like calc but with configurable decimal places: calcf "expr" decimals
    python3 -c "
import sys
try:
    result = eval('$1')
    print(f'{float(result):.${2:-3}f}')
except ZeroDivisionError:
    print('N/A')
except:
    print('N/A')
"
}

# ─── Separator ─────────────────────────────────────────────────────────────────
sep() { echo "────────────────────────────────────────────────────────"; }

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 0: CPU FREQUENCY & UTILIZATION  (perf-derived, not lscpu static value)
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SECTION 0: CPU Frequency & Utilization"
echo "  Effective values measured during workload execution"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RAW=$(collect_group \
    "task-clock,\
cpu-cycles,\
instructions" \
    "$WORKLOAD")

load_events "$RAW"

TASK_CLOCK_MS=${E["task-clock"]:-0}       # CPU time in milliseconds
CPU_CYCLES_S0=${E["cpu-cycles"]:-1}       # total cycles
INSTRS_S0=${E["instructions"]:-0}
CPUS_UTILIZED=${E["task-clock__metric"]:-0}  # "CPUs utilized" from perf metric-value

# Effective frequency: cycles / (task-clock in seconds) → GHz
# task-clock is in ms, so: cycles / (ms * 1e6) = GHz
EFF_FREQ_GHZ=$(calcf "($CPU_CYCLES_S0 / ($TASK_CLOCK_MS * 1e6))" 3)

# CPU utilization %:  CPUs utilized / total_cores * 100
CPU_UTIL_PCT=$(calcf "($CPUS_UTILIZED / $TOTAL_CORES) * 100" 2)

# CPU busy % on the cores that ran (CPUs utilized as direct % of 1 core = util per-core)
CPUS_UTIL_ABS=$(calcf "$CPUS_UTILIZED" 3)

printf "  %-40s %12s GHz\n" "CPU Operating Frequency (effective)"  "$EFF_FREQ_GHZ"
printf "  %-40s %14s%%\n"   "CPU Utilization (all cores)"          "$CPU_UTIL_PCT"
printf "  %-40s %12s CPUs\n" "CPUs Utilized (absolute)"            "$CPUS_UTIL_ABS"
sep
printf "  %-40s %15.0f\n" "task-clock CPU time (ms)"               $TASK_CLOCK_MS
printf "  %-40s %15.0f\n" "Total Cores on System"                  $TOTAL_CORES
echo ""
echo "  Note: Effective frequency reflects actual boost frequency"
echo "        during execution, not the static base freq from lscpu."
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 0.5: CPU PLACEMENT & CCD TOPOLOGY
# Tracks which cores the workload actually uses (including OS migrations)
# and detects cross-CCD execution (= separate L3 caches → extra latency)
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SECTION 0.5: CPU Placement & CCD Topology"
echo "  Which cores ran this workload, and which chiplets?"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

PLACEMENT_PY="${SCRIPT_DIR}/amd_cpu_placement.py"
PLACEMENT_JSON_TMP=$(mktemp /tmp/amd_placement_XXXXXX.json)

if [ -f "$PLACEMENT_PY" ]; then
    # Run the workload under the placement monitor.
    # --quiet suppresses human-readable so we can format ourselves,
    # --json-file writes the data we'll parse, stdout is the pretty print.
    python3 "$PLACEMENT_PY" --json-file "$PLACEMENT_JSON_TMP" -- $WORKLOAD

    # Parse key fields from JSON for the SUMMARY section later
    if [ -f "$PLACEMENT_JSON_TMP" ]; then
        PEAK_CPUS=$(python3 -c "
import json, sys
try:
    d = json.load(open('$PLACEMENT_JSON_TMP'))
    print(d.get('peak_parallel_cpus', '?'))
except:
    print('?')
")
        CORES_SEEN=$(python3 -c "
import json, sys
try:
    d = json.load(open('$PLACEMENT_JSON_TMP'))
    print(d.get('unique_cores_seen', '?'))
except:
    print('?')
")
        N_CCDS=$(python3 -c "
import json, sys
try:
    d = json.load(open('$PLACEMENT_JSON_TMP'))
    print(d.get('n_ccds_used', '?'))
except:
    print('?')
")
        CROSS_CCD=$(python3 -c "
import json, sys
try:
    d = json.load(open('$PLACEMENT_JSON_TMP'))
    print('YES' if d.get('cross_ccd_execution') else 'NO')
except:
    print('?')
")
        EXEC_MODE=$(python3 -c "
import json, sys
try:
    d = json.load(open('$PLACEMENT_JSON_TMP'))
    print(d.get('execution_mode', '?'))
except:
    print('?')
")
        rm -f "$PLACEMENT_JSON_TMP"
    fi
else
    echo "  [amd_cpu_placement.py not found — skipping CCD topology section]"
    echo "  Expected: $PLACEMENT_PY"
    PEAK_CPUS="?"
    CORES_SEEN="?"
    N_CCDS="?"
    CROSS_CCD="?"
    EXEC_MODE="?"
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 1: AMD PIPELINE UTILIZATION
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SECTION 1: AMD Pipeline Utilization (Dispatch Slots)"
echo "  AMD dispatches up to 6 ops per cycle"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RAW=$(collect_group \
    "de_no_dispatch_per_slot.no_ops_from_frontend,\
de_no_dispatch_per_slot.backend_stalls,\
de_src_op_disp.all,\
ex_ret_ops,\
ls_not_halted_cyc" \
    "$WORKLOAD")

load_events "$RAW"

FRONTEND=${E["de_no_dispatch_per_slot.no_ops_from_frontend"]:-0}
BACKEND=${E["de_no_dispatch_per_slot.backend_stalls"]:-0}
DISPATCHED=${E["de_src_op_disp.all"]:-0}
RETIRED=${E["ex_ret_ops"]:-0}
CYCLES=${E["ls_not_halted_cyc"]:-1}

TOTAL_SLOTS=$(calc "$CYCLES * 6")
FRONTEND_PCT=$(calc "($FRONTEND / ($CYCLES * 6)) * 100")
BACKEND_PCT=$(calc "($BACKEND / ($CYCLES * 6)) * 100")
BADSPEC_PCT=$(calc "(($DISPATCHED - $RETIRED) / ($CYCLES * 6)) * 100")
RETIRING_PCT=$(calc "($RETIRED / ($CYCLES * 6)) * 100")

printf "  %-40s %15.0f\n" "Active CPU Cycles"              $CYCLES
printf "  %-40s %15.0f\n" "Total Dispatch Slots (6x)"      $TOTAL_SLOTS
sep
printf "  %-40s %14s%%\n" "Frontend Bound"                  "$FRONTEND_PCT"
printf "    %-38s %15.0f\n" "└─ Unused Slots (Frontend)"   $FRONTEND
printf "  %-40s %14s%%\n" "Backend Bound"                   "$BACKEND_PCT"
printf "    %-38s %15.0f\n" "└─ Unused Slots (Backend)"    $BACKEND
printf "  %-40s %14s%%\n" "Bad Speculation"                 "$BADSPEC_PCT"
printf "    %-38s %15.0f\n" "└─ Dispatched Ops"            $DISPATCHED
printf "    %-38s %15.0f\n" "└─ Retired Ops"               $RETIRED
printf "  %-40s %14s%%\n" "Retiring (Useful Work)"          "$RETIRING_PCT"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 2: BACKEND BREAKDOWN (Memory vs CPU Stalls)
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SECTION 2: Backend Bound Breakdown"
echo "  Memory subsystem vs CPU execution stalls"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RAW=$(collect_group \
    "ex_no_retire.load_not_complete,\
ex_no_retire.not_complete,\
ls_not_halted_cyc" \
    "$WORKLOAD")

load_events "$RAW"

LOAD_NOT_COMPLETE=${E["ex_no_retire.load_not_complete"]:-0}
NOT_COMPLETE=${E["ex_no_retire.not_complete"]:-1}
CYCLES2=${E["ls_not_halted_cyc"]:-1}

MEM_RATIO=$(calc "($LOAD_NOT_COMPLETE / $NOT_COMPLETE) * 100")
CPU_RATIO=$(calc "((1 - ($LOAD_NOT_COMPLETE / $NOT_COMPLETE)) * 100)")
BACKEND_MEM_PCT=$(calc "(($BACKEND / ($CYCLES2 * 6)) * ($LOAD_NOT_COMPLETE / $NOT_COMPLETE)) * 100")
BACKEND_CPU_PCT=$(calc "(($BACKEND / ($CYCLES2 * 6)) * (1 - ($LOAD_NOT_COMPLETE / $NOT_COMPLETE))) * 100")

printf "  %-40s %15.0f\n" "Total Non-Retire Events"            $NOT_COMPLETE
printf "  %-40s %15.0f\n" "Load Not Complete (Memory Stalls)"  $LOAD_NOT_COMPLETE
sep
printf "  %-40s %14s%%\n" "Backend Bound - Memory"             "$BACKEND_MEM_PCT"
printf "  %-40s %14s%%\n" "Backend Bound - CPU"                "$BACKEND_CPU_PCT"
printf "  %-40s %14s%%\n" "└─ Stalls from Memory Subsystem"    "$MEM_RATIO"
printf "  %-40s %14s%%\n" "└─ Stalls from CPU Execution"       "$CPU_RATIO"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 3: BRANCH PREDICTION
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SECTION 3: Branch Prediction"
echo "  AMD TAGE predictor efficiency"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RAW=$(collect_group \
    "ex_ret_brn_misp,\
ex_ret_brn,\
cpu-cycles,\
instructions" \
    "$WORKLOAD")

load_events "$RAW"

MISP=${E["ex_ret_brn_misp"]:-0}
BRANCHES=${E["ex_ret_brn"]:-1}
CPU_CYCLES=${E["cpu-cycles"]:-1}
INSTRS=${E["instructions"]:-0}

MISP_RATIO=$(calc "($MISP / $BRANCHES) * 100")
IPC=$(calc "$INSTRS / $CPU_CYCLES")

printf "  %-40s %15.0f\n" "Total Branches Retired"             $BRANCHES
printf "  %-40s %15.0f\n" "Branch Mispredictions"              $MISP
printf "  %-40s %15.0f\n" "Instructions Retired"               $INSTRS
printf "  %-40s %15.0f\n" "CPU Cycles"                         $CPU_CYCLES
sep
printf "  %-40s %14s%%\n" "Branch Misprediction Rate"          "$MISP_RATIO"
printf "  %-40s %15s\n"   "Instructions per Cycle (IPC)"       "$IPC"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 4: L2 CACHE PERFORMANCE
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SECTION 4: L2 Cache Performance"
echo "  AMD advantage: 1MB L2 per core (vs Intel 256-512KB)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

RAW=$(collect_group \
    "l2_cache_req_stat.dc_hit_in_l2,\
l2_cache_req_stat.ls_rd_blk_c,\
l2_cache_req_stat.ic_fill_miss,\
l2_cache_req_stat.ic_hit_in_l2" \
    "$WORKLOAD")

load_events "$RAW"

L2_DC_HITS=${E["l2_cache_req_stat.dc_hit_in_l2"]:-0}
L2_DC_MISS=${E["l2_cache_req_stat.ls_rd_blk_c"]:-0}
L2_IC_MISS=${E["l2_cache_req_stat.ic_fill_miss"]:-0}
L2_IC_HITS=${E["l2_cache_req_stat.ic_hit_in_l2"]:-0}

L2_DC_HIT_RATE=$(calc "($L2_DC_HITS / ($L2_DC_HITS + $L2_DC_MISS + 0.0001)) * 100")
L2_IC_HIT_RATE=$(calc "($L2_IC_HITS / ($L2_IC_HITS + $L2_IC_MISS + 0.0001)) * 100")

printf "  %-40s %15.0f\n" "L2 Data Cache Hits"                 $L2_DC_HITS
printf "  %-40s %15.0f\n" "L2 Data Cache Misses"               $L2_DC_MISS
printf "  %-40s %15.0f\n" "L2 Instruction Cache Hits"          $L2_IC_HITS
printf "  %-40s %15.0f\n" "L2 Instruction Cache Misses"        $L2_IC_MISS
sep
printf "  %-40s %14s%%\n" "L2 Data Cache Hit Rate"             "$L2_DC_HIT_RATE"
printf "  %-40s %14s%%\n" "L2 Instruction Cache Hit Rate"      "$L2_IC_HIT_RATE"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
printf "  %-40s %12s GHz\n" "CPU Operating Frequency (effective)"  "$EFF_FREQ_GHZ"
printf "  %-40s %14s%%\n" "CPU Utilization (all cores)"          "$CPU_UTIL_PCT"
sep
printf "  %-40s %14s\n"   "Execution mode"                       "$EXEC_MODE"
printf "  %-40s %14s\n"   "Peak concurrent CPUs"                 "$PEAK_CPUS"
printf "  %-40s %14s\n"   "Unique cores touched (incl. migrations)" "$CORES_SEEN"
printf "  %-40s %14s\n"   "CCDs (chiplets) used"                 "$N_CCDS"
printf "  %-40s %14s\n"   "Cross-CCD execution"                  "$CROSS_CCD"
sep
printf "  %-40s %14s%%\n" "Frontend Bound"        "$FRONTEND_PCT"
printf "  %-40s %14s%%\n" "Backend Bound"          "$BACKEND_PCT"
printf "    %-38s %14s%%\n" "└─ Memory"            "$BACKEND_MEM_PCT"
printf "    %-38s %14s%%\n" "└─ CPU"               "$BACKEND_CPU_PCT"
printf "  %-40s %14s%%\n" "Bad Speculation"         "$BADSPEC_PCT"
printf "  %-40s %14s%%\n" "Retiring (Useful Work)"  "$RETIRING_PCT"
sep
printf "  %-40s %14s%%\n" "Branch Misprediction Rate"   "$MISP_RATIO"
printf "  %-40s %15s\n"   "IPC"                         "$IPC"
printf "  %-40s %14s%%\n" "L2 Data Cache Hit Rate"      "$L2_DC_HIT_RATE"
echo ""