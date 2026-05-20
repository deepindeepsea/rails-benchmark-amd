#!/usr/bin/env python3
"""
AMD Performance HTML Report Generator
Inspired by Intel PerfSpect's HTML output format.

Collects AMD pipeline metrics via perf stat and produces a self-contained
HTML report with sidebar navigation, data tables, and Chart.js visualizations.

Usage:
    python3 amd_perf_html_report.py [workload_command] [output.html]

Examples:
    python3 amd_perf_html_report.py "sleep 2" amd_report.html
    python3 amd_perf_html_report.py "openssl speed md5" amd_report.html
    python3 amd_perf_html_report.py "dd if=/dev/zero of=/dev/null bs=1M count=500" amd_report.html
"""

import sys
import json
import subprocess
import platform
import datetime
import os
import argparse
import html as html_escape_module
import shutil

# ─────────────────────────────────────────────────────────────────────────────
# Event Group Definitions  (confirmed working on AMD Zen4/Zen5 baremetal)
# ─────────────────────────────────────────────────────────────────────────────

EVENT_GROUPS = {
    # task-clock first: gives effective frequency + CPU utilization via metric-value
    "cpu_freq_util": (
        "task-clock,"
        "cpu-cycles,"
        "instructions"
    ),
    "pipeline_l1": (
        "de_no_dispatch_per_slot.no_ops_from_frontend,"
        "de_no_dispatch_per_slot.backend_stalls,"
        "de_src_op_disp.all,"
        "ex_ret_ops,"
        "ls_not_halted_cyc"
    ),
    "backend_breakdown": (
        "ex_no_retire.load_not_complete,"
        "ex_no_retire.not_complete,"
        "ls_not_halted_cyc"
    ),
    "branch_prediction": (
        "ex_ret_brn_misp,"
        "ex_ret_brn,"
        "cpu-cycles,"
        "instructions"
    ),
    "l2_cache": (
        "l2_cache_req_stat.dc_hit_in_l2,"
        "l2_cache_req_stat.ls_rd_blk_c,"
        "l2_cache_req_stat.ic_fill_miss,"
        "l2_cache_req_stat.ic_hit_in_l2"
    ),
}

# ─────────────────────────────────────────────────────────────────────────────
# perf stat collection
# ─────────────────────────────────────────────────────────────────────────────

def collect_events(events: str, workload: str) -> dict:
    """
    Run perf stat -j and return {event_name: float} dict.
    Also stores metric-value as {event_name}__metric (e.g. task-clock__metric
    = CPUs utilized float, which is how perf reports utilization).
    """
    cmd = f'perf stat -j -e "{events}" -- {workload} 2>&1'
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=120)
        output = result.stdout + result.stderr
    except subprocess.TimeoutExpired:
        print("Warning: perf stat timed out", file=sys.stderr)
        return {}

    values = {}
    for line in output.splitlines():
        line = line.strip()
        if not line or '"event"' not in line:
            continue
        try:
            obj = json.loads(line)
            event = obj.get("event", "").strip()
            val_str = obj.get("counter-value", "0").replace(",", "").strip()
            if val_str in ("<not counted>", "<not supported>", ""):
                val = 0.0
            else:
                val = float(val_str)
            if event:
                values[event] = val
                # Capture metric-value if present (e.g. "CPUs utilized" from task-clock)
                mval_str = obj.get("metric-value", "")
                if mval_str and mval_str not in ("<not counted>", "<not supported>", ""):
                    try:
                        values[event + "__metric"] = float(str(mval_str).replace(",", ""))
                    except ValueError:
                        pass
        except (json.JSONDecodeError, ValueError):
            pass
    return values


def safe_div(num, denom, default=0.0):
    try:
        if denom == 0:
            return default
        return num / denom
    except Exception:
        return default


# ─────────────────────────────────────────────────────────────────────────────
# Metric Calculation
# ─────────────────────────────────────────────────────────────────────────────

def get_total_cores() -> int:
    try:
        return os.cpu_count() or 1
    except Exception:
        return 1


def calculate_metrics(events: dict) -> dict:
    m = {}

    # ── CPU Frequency & Utilization ───────────────────────────────────────────
    # task-clock is in milliseconds of CPU time consumed
    # task-clock__metric = "CPUs utilized" (float) from perf's built-in metric
    task_clock_ms   = events.get("task-clock", 0)          # ms
    cpus_utilized   = events.get("task-clock__metric", 0)  # e.g. 1.99 CPUs
    cpu_cycles_freq = events.get("cpu-cycles", 1)          # from freq group

    total_cores = get_total_cores()

    # Effective frequency: cycles / (task_clock_ms * 1e6) = GHz
    # (task_clock_ms * 1e-3 seconds, divide by 1e9 for GHz → same as / 1e6*ms)
    eff_freq_ghz = safe_div(cpu_cycles_freq, task_clock_ms * 1e6)
    cpu_util_pct = safe_div(cpus_utilized, total_cores) * 100

    m["CPU Operating Frequency (GHz)"] = round(eff_freq_ghz, 3)
    m["CPU Utilization %"]             = round(cpu_util_pct, 2)
    m["CPUs Utilized (abs)"]           = round(cpus_utilized, 3)
    m["_Total Cores"]                  = total_cores
    m["_task-clock ms"]                = task_clock_ms

    # Raw events
    frontend     = events.get("de_no_dispatch_per_slot.no_ops_from_frontend", 0)
    backend      = events.get("de_no_dispatch_per_slot.backend_stalls", 0)
    dispatched   = events.get("de_src_op_disp.all", 0)
    retired      = events.get("ex_ret_ops", 0)
    cycles       = events.get("ls_not_halted_cyc", 1)

    load_nc      = events.get("ex_no_retire.load_not_complete", 0)
    not_complete = events.get("ex_no_retire.not_complete", 1)
    cycles2      = events.get("ls_not_halted_cyc", 1)

    misp         = events.get("ex_ret_brn_misp", 0)
    branches     = events.get("ex_ret_brn", 1)
    cpu_cycles   = events.get("cpu-cycles", 1)
    instructions = events.get("instructions", 0)

    l2_dc_hits   = events.get("l2_cache_req_stat.dc_hit_in_l2", 0)
    l2_dc_miss   = events.get("l2_cache_req_stat.ls_rd_blk_c", 0)
    l2_ic_miss   = events.get("l2_cache_req_stat.ic_fill_miss", 0)
    l2_ic_hits   = events.get("l2_cache_req_stat.ic_hit_in_l2", 0)

    # Pipeline L1
    total_slots      = cycles * 6
    m["Frontend Bound %"]       = safe_div(frontend, total_slots) * 100
    m["Backend Bound %"]        = safe_div(backend, total_slots) * 100
    m["Bad Speculation %"]      = safe_div(dispatched - retired, total_slots) * 100
    m["Retiring %"]             = safe_div(retired, total_slots) * 100

    # Backend breakdown
    mem_ratio = safe_div(load_nc, not_complete)
    m["Backend Memory Bound %"] = m["Backend Bound %"] * mem_ratio
    m["Backend CPU Bound %"]    = m["Backend Bound %"] * (1 - mem_ratio)
    m["Memory Stall Ratio %"]   = mem_ratio * 100
    m["CPU Stall Ratio %"]      = (1 - mem_ratio) * 100

    # Branch prediction
    m["Branch Misprediction Rate %"] = safe_div(misp, branches) * 100
    m["IPC"]                         = safe_div(instructions, cpu_cycles)

    # L2 Cache
    m["L2 Data Cache Hit Rate %"]        = safe_div(l2_dc_hits, l2_dc_hits + l2_dc_miss + 1e-6) * 100
    m["L2 Instruction Cache Hit Rate %"] = safe_div(l2_ic_hits, l2_ic_hits + l2_ic_miss + 1e-6) * 100

    # Raw counts (for the detail tables)
    m["_Active Cycles"]         = cycles
    m["_Total Dispatch Slots"]  = total_slots
    m["_Frontend Unused Slots"] = frontend
    m["_Backend Unused Slots"]  = backend
    m["_Dispatched Ops"]        = dispatched
    m["_Retired Ops"]           = retired
    m["_Total Branches"]        = branches
    m["_Branch Mispredicts"]    = misp
    m["_Instructions"]          = instructions
    m["_CPU Cycles"]            = cpu_cycles
    m["_L2 DC Hits"]            = l2_dc_hits
    m["_L2 DC Misses"]          = l2_dc_miss
    m["_L2 IC Hits"]            = l2_ic_hits
    m["_L2 IC Misses"]          = l2_ic_miss
    m["_Non-Retire Events"]     = not_complete
    m["_Load Not Complete"]     = load_nc

    return m


# ─────────────────────────────────────────────────────────────────────────────
# CPU Placement / CCD Topology Collection
# ─────────────────────────────────────────────────────────────────────────────

def collect_placement_data(workload: str) -> dict:
    """
    Run the workload under amd_cpu_placement.py and return its JSON report.
    Falls back to an empty dict if the script is not found or fails.

    The placement script lives alongside this file.
    """
    script_dir  = os.path.dirname(os.path.abspath(__file__))
    placement_py = os.path.join(script_dir, "amd_cpu_placement.py")

    if not os.path.isfile(placement_py):
        print(f"  [skip CCD topology: {placement_py} not found]", file=sys.stderr)
        return {}

    try:
        cmd = [sys.executable, placement_py, "--json", "--"] + workload.split()
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        data = json.loads(result.stdout)
        return data
    except Exception as e:
        print(f"  [CCD topology collection failed: {e}]", file=sys.stderr)
        return {}


# ─────────────────────────────────────────────────────────────────────────────
# HTML Generation  (PerfSpect-inspired style)
# ─────────────────────────────────────────────────────────────────────────────

HTML_HEAD = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>AMD Performance Analysis Report</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" href="https://unpkg.com/normalize.css@8.0.1/normalize.css"
        crossorigin="anonymous" referrerpolicy="no-referrer"/>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/purecss@3.0.0/build/pure-min.css"
        crossorigin="anonymous" referrerpolicy="no-referrer"/>
  <script src="https://unpkg.com/chart.js@3.7.1/dist/chart.min.js"
          crossorigin="anonymous" referrerpolicy="no-referrer"></script>
  <style>
    /* ── Layout ── */
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
           background: #f8f9fa; color: #212529; margin: 0; }
    .sidebar {
      height: 100%; width: 220px; position: fixed; top: 0; left: 0;
      background: #1a1a2e; overflow-x: hidden; padding-top: 70px; z-index: 100;
    }
    .sidebar .brand {
      position: absolute; top: 0; left: 0; right: 0;
      background: #e53935; color: #fff; padding: 14px 16px;
      font-size: 15px; font-weight: 700; letter-spacing: 0.5px;
    }
    .sidebar a {
      display: block; padding: 9px 16px 9px 24px;
      color: #9e9e9e; text-decoration: none; font-size: 13px;
      border-left: 3px solid transparent; transition: 0.2s;
    }
    .sidebar a:hover, .sidebar a.active {
      color: #fff; border-left-color: #e53935; background: rgba(255,255,255,0.05);
    }
    .sidebar h3 {
      color: #616161; font-size: 10px; text-transform: uppercase;
      letter-spacing: 1px; padding: 14px 16px 4px 24px; margin: 0;
    }
    .content { margin-left: 220px; padding: 30px 40px 60px; max-width: 1100px; }

    /* ── Section headers ── */
    .section-title {
      font-size: 20px; font-weight: 600; color: #212529;
      border-bottom: 2px solid #e53935; padding-bottom: 6px; margin-top: 40px;
    }
    .section-subtitle {
      font-size: 13px; color: #6c757d; margin: 4px 0 16px;
    }

    /* ── Info header ── */
    .info-bar {
      background: #1a1a2e; color: #ccc; border-radius: 6px;
      padding: 14px 20px; margin-bottom: 30px; font-size: 13px;
      display: flex; flex-wrap: wrap; gap: 20px;
    }
    .info-bar span { color: #fff; font-weight: 600; }

    /* ── Tables ── */
    .pure-table { width: 100%; font-size: 13px; }
    .pure-table td, .pure-table th { padding: 8px 12px; }
    .pure-table-striped tr:nth-child(odd) td { background: #f1f3f5; }
    .metric-table { margin-bottom: 28px; border-radius: 6px;
                    overflow: hidden; box-shadow: 0 1px 4px rgba(0,0,0,.08); }
    .metric-table td:first-child { font-weight: 600; color: #495057; width: 55%; }
    .metric-table td:last-child  { text-align: right; font-family: monospace; font-size: 14px; }
    .good  { color: #2e7d32; font-weight: 700; }
    .warn  { color: #f57c00; font-weight: 700; }
    .bad   { color: #c62828; font-weight: 700; }

    /* ── Summary gauge row ── */
    .gauge-row { display: flex; gap: 20px; flex-wrap: wrap; margin-bottom: 28px; }
    .gauge-card {
      background: #fff; border-radius: 8px; padding: 16px 20px;
      box-shadow: 0 1px 4px rgba(0,0,0,.1); flex: 1; min-width: 160px; text-align: center;
    }
    .gauge-card .label { font-size: 11px; text-transform: uppercase;
                         letter-spacing: 0.8px; color: #868e96; margin-bottom: 6px; }
    .gauge-card .value { font-size: 28px; font-weight: 700; }
    .gauge-card .unit  { font-size: 12px; color: #adb5bd; margin-top: 2px; }

    /* ── Chart containers ── */
    .chart-wrap { background: #fff; border-radius: 8px; padding: 20px;
                  box-shadow: 0 1px 4px rgba(0,0,0,.08); margin-bottom: 28px; }
    .chart-wrap canvas { max-height: 280px; }

    /* ── Interpretation boxes ── */
    .insight {
      background: #fff3cd; border-left: 4px solid #ffc107;
      border-radius: 4px; padding: 12px 16px; margin-bottom: 16px; font-size: 13px;
    }
    .insight.good { background: #d4edda; border-left-color: #28a745; }
    .insight.bad  { background: #f8d7da; border-left-color: #dc3545; }
    .insight strong { display: block; margin-bottom: 4px; font-size: 13px; }

    /* ── Footer ── */
    .footer { color: #adb5bd; font-size: 12px; margin-top: 50px; border-top: 1px solid #dee2e6; padding-top: 16px; }
  </style>
</head>
"""

SIDEBAR = """<div class="sidebar">
  <div class="brand">AMD Perf Report</div>
  <h3>Sections</h3>
  <a href="#system-info">CPU Freq &amp; Utilization</a>
  <a href="#ccd-topology">CCD Topology</a>
  <a href="#pipeline-summary">Pipeline Summary</a>
  <a href="#pipeline-l1">Pipeline Utilization</a>
  <a href="#backend-breakdown">Backend Breakdown</a>
  <a href="#branch-prediction">Branch Prediction</a>
  <a href="#l2-cache">L2 Cache</a>
  <a href="#interpretation">Insights</a>
</div>
"""


def pct_class(val, good_below=20, bad_above=50):
    """Return CSS class based on percentage thresholds (lower = better)."""
    if val < good_below:
        return "good"
    if val > bad_above:
        return "bad"
    return "warn"


def fmt_pct(v):
    return f"{v:.2f}%"


def fmt_int(v):
    return f"{int(v):,}"


def fmt_f(v, decimals=2):
    return f"{v:.{decimals}f}"


def metric_row(label, value_str, css_class=""):
    cls = f' class="{css_class}"' if css_class else ""
    return f"<tr><td>{html_escape_module.escape(label)}</td><td{cls}>{value_str}</td></tr>\n"


def table_block(rows_html, table_id=""):
    id_attr = f' id="{table_id}"' if table_id else ""
    return (
        f'<div class="metric-table"{id_attr}>'
        f'<table class="pure-table pure-table-striped"><tbody>'
        f'{rows_html}</tbody></table></div>'
    )


def generate_html(metrics: dict, workload: str, cpu_info: str, timestamp: str,
                  placement: dict = None) -> str:
    sb = [HTML_HEAD, "<body>", SIDEBAR, '<div class="content">']

    # ── Report header ──────────────────────────────────────────────────────
    sb.append('<h1 style="font-size:26px;font-weight:700;color:#1a1a2e;margin-bottom:6px;">'
              'AMD Performance Analysis Report</h1>')

    eff_freq = metrics.get("CPU Operating Frequency (GHz)", 0)
    cpu_util = metrics.get("CPU Utilization %", 0)
    total_cores = metrics.get("_Total Cores", 1)

    sb.append(f'<div class="info-bar">'
              f'<div>CPU: <span>{html_escape_module.escape(cpu_info)}</span></div>'
              f'<div>Effective Freq: <span>{eff_freq:.3f} GHz</span></div>'
              f'<div>CPU Util: <span>{cpu_util:.1f}% ({total_cores} cores)</span></div>'
              f'<div>Workload: <span>{html_escape_module.escape(workload)}</span></div>'
              f'<div>Generated: <span>{html_escape_module.escape(timestamp)}</span></div>'
              f'</div>')

    # ── System info anchor ─────────────────────────────────────────────────
    sb.append('<div id="system-info">')
    sb.append('<div class="section-title">CPU Frequency &amp; Utilization</div>')
    sb.append('<div class="section-subtitle">'
              'Measured during workload execution via perf task-clock and cpu-cycles '
              '(effective boost frequency, not static base from lscpu)</div>')

    cpus_abs   = metrics.get("CPUs Utilized (abs)", 0)
    task_ms    = metrics.get("_task-clock ms", 0)

    # Gauge cards for freq + utilization
    sb.append('<div class="gauge-row">')

    freq_css = "good" if eff_freq > 3.0 else ("warn" if eff_freq > 2.0 else "bad")
    sb.append(f'<div class="gauge-card">'
              f'<div class="label">Effective Frequency</div>'
              f'<div class="value {freq_css}">{eff_freq:.3f}</div>'
              f'<div class="unit">GHz (boost)</div>'
              f'</div>')

    util_css = "good" if cpu_util > 80 else ("warn" if cpu_util > 30 else "bad")
    sb.append(f'<div class="gauge-card">'
              f'<div class="label">CPU Utilization</div>'
              f'<div class="value {util_css}">{cpu_util:.1f}</div>'
              f'<div class="unit">% of all {total_cores} cores</div>'
              f'</div>')

    sb.append(f'<div class="gauge-card">'
              f'<div class="label">CPUs Utilized</div>'
              f'<div class="value">{cpus_abs:.3f}</div>'
              f'<div class="unit">cores (absolute)</div>'
              f'</div>')

    sb.append('</div>')  # gauge-row

    rows = ""
    rows += metric_row("CPU Operating Frequency (effective)",
                       f"{eff_freq:.3f} GHz",
                       freq_css)
    rows += metric_row("  └─ Derived from: cpu-cycles / (task-clock in seconds)",
                       "")
    rows += metric_row("CPU Utilization (% of all system cores)",
                       fmt_pct(cpu_util),
                       util_css)
    rows += metric_row("CPUs Utilized (absolute count)",
                       f"{cpus_abs:.3f} CPUs")
    rows += metric_row("Total Cores on System",
                       str(total_cores))
    rows += metric_row("task-clock CPU time consumed",
                       f"{task_ms:,.0f} ms")
    sb.append(table_block(rows))
    sb.append('</div>')  # system-info

    # ── CCD Topology Section ───────────────────────────────────────────────
    sb.append('<div id="ccd-topology">')
    sb.append('<div class="section-title">CPU Placement &amp; CCD Topology</div>')
    sb.append('<div class="section-subtitle">'
              'Which cores ran this workload, and which chiplets (CCDs) are involved? '
              'Each AMD EPYC CCD contains 8 cores sharing one L3 cache. '
              'Cross-CCD execution means threads cross separate L3 domains, '
              'introducing ~100&nbsp;ns cache-to-cache latency.</div>')

    if placement:
        peak     = placement.get("peak_parallel_cpus", 0)
        n_seen   = placement.get("unique_cores_seen", 0)
        cores    = placement.get("cores_seen", [])
        n_ccds   = placement.get("n_ccds_used", 0)
        ccds     = placement.get("ccds_used", {})          # {"0": [0,1,...], ...}
        cross    = placement.get("cross_ccd_execution", False)
        mode     = placement.get("execution_mode", "?")
        mig_note = placement.get("migration_note", "")
        l3_ccd   = placement.get("l3_per_ccd_mb", 32)
        l3_total = placement.get("total_l3_accessible_mb", 0)
        l3_thr   = placement.get("l3_per_thread_mb", 0)
        sys_ccds = placement.get("total_system_ccds", "?")

        # Gauge cards
        sb.append('<div class="gauge-row">')

        peak_css = "good" if peak == 1 else ("warn" if peak <= 8 else "bad")
        sb.append(f'<div class="gauge-card">'
                  f'<div class="label">Peak Parallel CPUs</div>'
                  f'<div class="value {peak_css}">{peak}</div>'
                  f'<div class="unit">true concurrency</div>'
                  f'</div>')

        sb.append(f'<div class="gauge-card">'
                  f'<div class="label">Unique Cores Touched</div>'
                  f'<div class="value">{n_seen}</div>'
                  f'<div class="unit">incl. OS migrations</div>'
                  f'</div>')

        ccd_css = "good" if not cross else "bad"
        sb.append(f'<div class="gauge-card">'
                  f'<div class="label">CCDs Used</div>'
                  f'<div class="value {ccd_css}">{n_ccds} / {sys_ccds}</div>'
                  f'<div class="unit">{"cross-CCD!" if cross else "single CCD"}</div>'
                  f'</div>')

        sb.append(f'<div class="gauge-card">'
                  f'<div class="label">L3 Accessible</div>'
                  f'<div class="value">{l3_total}</div>'
                  f'<div class="unit">MB ({n_ccds} × {l3_ccd}&nbsp;MB)</div>'
                  f'</div>')

        sb.append('</div>')  # gauge-row

        # Detail table
        rows = ""
        rows += metric_row("Execution mode",                    mode)
        rows += metric_row("Peak concurrent CPUs (true parallelism)",
                           str(peak),
                           "good" if peak == 1 else "")
        rows += metric_row("Unique cores touched (incl. migrations)",
                           str(n_seen))
        rows += metric_row("Core numbers seen",
                           str(cores))
        rows += metric_row("─" * 40, "")
        rows += metric_row("CCDs (chiplets) active",
                           f"{n_ccds} out of {sys_ccds} total")
        for ccd_id, cpu_list in sorted(ccds.items(), key=lambda x: int(x[0])):
            rows += metric_row(f"  └─ CCD {ccd_id}",
                               f"cores {cpu_list}")
        rows += metric_row("─" * 40, "")
        cross_label = "YES — cross-CCD latency applies" if cross else "NO — single CCD, shared L3"
        cross_css   = "bad" if cross else "good"
        rows += metric_row("Cross-CCD execution",           cross_label, cross_css)
        rows += metric_row("L3 cache accessible (total)",   f"{l3_total} MB")
        rows += metric_row("L3 per thread (peak)",          f"{l3_thr} MB")
        if mig_note:
            rows += metric_row("OS migration note", mig_note)
        sb.append(table_block(rows))

        # Insight box for cross-CCD
        if cross:
            first_ccd = sorted(ccds.keys(), key=int)[0]
            first_cores = ccds[first_ccd]
            pin_range = f"{first_cores[0]}-{first_cores[-1]}"
            sb.append(
                f'<div class="insight bad">'
                f'<strong>Cross-CCD Execution Detected ({n_ccds} CCDs)</strong>'
                f'Threads are running across {n_ccds} separate L3 cache domains. '
                f'Cache-to-cache transfers between CCDs add ~100&nbsp;ns latency. '
                f'To eliminate this, pin the workload to a single CCD:<br>'
                f'<code>taskset -c {pin_range} &lt;workload&gt;</code> '
                f'or <code>numactl --physcpubind={pin_range} &lt;workload&gt;</code>'
                f'</div>'
            )
        elif peak == 1 and n_seen > 1:
            sb.append(
                f'<div class="insight good">'
                f'<strong>Single-Threaded — CCD-Local Execution</strong>'
                f'One thread active at a time. The OS migrated it across {n_seen} cores '
                f'(context-switch scheduling), but all cores are within CCD {list(ccds.keys())[0]}, '
                f'so no cross-CCD latency applies. '
                f'The full {l3_ccd}&nbsp;MB L3 is exclusively available to this thread\'s data.'
                f'</div>'
            )
        else:
            sb.append(
                f'<div class="insight good">'
                f'<strong>Single-CCD Execution</strong>'
                f'All {peak} thread(s) run within CCD {list(ccds.keys())[0]}. '
                f'Shared {l3_ccd}&nbsp;MB L3 — no cross-CCD latency.'
                f'</div>'
            )

        # CCD bar chart (cores per CCD)
        ccd_labels = [f"CCD {k}" for k in sorted(ccds.keys(), key=int)]
        ccd_counts = [len(ccds[k]) for k in sorted(ccds.keys(), key=int)]
        bar_colors = ['#e53935' if cross else '#2e7d32'] * len(ccd_labels)

        sb.append('<div class="chart-wrap">')
        sb.append('<canvas id="ccdChart" style="max-height:200px;"></canvas>')
        sb.append(f"""<script>
new Chart(document.getElementById('ccdChart'), {{
  type: 'bar',
  data: {{
    labels: {json.dumps(ccd_labels)},
    datasets: [{{
      label: 'Unique Cores Seen per CCD',
      data: {json.dumps(ccd_counts)},
      backgroundColor: {json.dumps(bar_colors)}
    }}]
  }},
  options: {{
    plugins: {{
      title: {{ display: true,
                text: 'Core Distribution Across CCDs (unique cores touched, incl. migrations)' }}
    }},
    scales: {{
      y: {{ beginAtZero: true, ticks: {{ stepSize: 1 }},
            title: {{ display: true, text: 'Unique cores' }} }}
    }}
  }}
}});
</script>""")
        sb.append('</div>')  # chart-wrap

    else:
        sb.append('<div class="insight"><strong>CCD topology data not available.</strong>'
                  'Run with amd_cpu_placement.py alongside this script to capture '
                  'core placement information.</div>')

    sb.append('</div>')  # ccd-topology

    # ── Pipeline Summary cards ─────────────────────────────────────────────
    sb.append('<div id="pipeline-summary">')
    sb.append('<div class="section-title">Pipeline Utilization Summary</div>')
    sb.append('<div class="section-subtitle">'
              'AMD dispatches up to 6 micro-ops per cycle. Each category shows '
              'what fraction of those slots were used for that purpose.</div>')

    # Gauge cards row
    sb.append('<div class="gauge-row">')
    for label, key, good_b, bad_a in [
        ("Frontend Bound",   "Frontend Bound %",   15, 35),
        ("Backend Bound",    "Backend Bound %",    20, 45),
        ("Bad Speculation",  "Bad Speculation %",  5,  20),
        ("Retiring",         "Retiring %",         50, 100),  # higher is better — invert
    ]:
        val = metrics.get(key, 0)
        # For Retiring, higher is better
        if label == "Retiring":
            css = "good" if val > 50 else ("warn" if val > 30 else "bad")
        else:
            css = pct_class(val, good_b, bad_a)
        sb.append(f'<div class="gauge-card">'
                  f'<div class="label">{html_escape_module.escape(label)}</div>'
                  f'<div class="value {css}">{val:.1f}</div>'
                  f'<div class="unit">% of slots</div>'
                  f'</div>')
    sb.append('</div>')  # gauge-row

    # Pipeline donut chart
    fe  = metrics.get("Frontend Bound %", 0)
    be  = metrics.get("Backend Bound %", 0)
    bs  = max(metrics.get("Bad Speculation %", 0), 0)
    ret = metrics.get("Retiring %", 0)

    sb.append('<div class="chart-wrap">')
    sb.append('<canvas id="pipelineChart" style="max-width:400px;max-height:300px;'
              'display:block;margin:auto;"></canvas>')
    sb.append(f"""<script>
new Chart(document.getElementById('pipelineChart'), {{
  type: 'doughnut',
  data: {{
    labels: ['Frontend Bound','Backend Bound','Bad Speculation','Retiring'],
    datasets: [{{
      data: [{fe:.2f},{be:.2f},{bs:.2f},{ret:.2f}],
      backgroundColor: ['#f57c00','#1565c0','#6a1a6a','#2e7d32'],
      borderWidth: 2, borderColor: '#fff'
    }}]
  }},
  options: {{
    plugins: {{
      legend: {{ position: 'bottom' }},
      title: {{ display: true, text: 'Pipeline Slot Distribution (%)', font: {{ size: 15 }} }}
    }}
  }}
}});
</script>""")
    sb.append('</div>')  # chart-wrap
    sb.append('</div>')  # pipeline-summary

    # ── Section 1: Pipeline L1 detail ─────────────────────────────────────
    sb.append('<div id="pipeline-l1">')
    sb.append('<div class="section-title">Section 1 — AMD Pipeline Utilization</div>')
    sb.append('<div class="section-subtitle">Dispatch slot analysis (6 slots × CPU cycles)</div>')

    rows = ""
    rows += metric_row("Active CPU Cycles",         fmt_int(metrics.get("_Active Cycles", 0)))
    rows += metric_row("Total Dispatch Slots (6×)", fmt_int(metrics.get("_Total Dispatch Slots", 0)))
    rows += metric_row("─" * 40, "")
    rows += metric_row("Frontend Bound",
                       fmt_pct(fe),
                       pct_class(fe, 15, 35))
    rows += metric_row("  └─ Unused slots (frontend stalls)",
                       fmt_int(metrics.get("_Frontend Unused Slots", 0)))
    rows += metric_row("Backend Bound",
                       fmt_pct(be),
                       pct_class(be, 20, 45))
    rows += metric_row("  └─ Unused slots (backend stalls)",
                       fmt_int(metrics.get("_Backend Unused Slots", 0)))
    rows += metric_row("Bad Speculation",
                       fmt_pct(bs),
                       pct_class(bs, 5, 20))
    rows += metric_row("  └─ Dispatched ops",   fmt_int(metrics.get("_Dispatched Ops", 0)))
    rows += metric_row("  └─ Retired ops",       fmt_int(metrics.get("_Retired Ops", 0)))
    rows += metric_row("Retiring (Useful Work)",
                       fmt_pct(ret),
                       "good" if ret > 50 else ("warn" if ret > 30 else "bad"))
    sb.append(table_block(rows))
    sb.append('</div>')

    # ── Section 2: Backend Breakdown ──────────────────────────────────────
    sb.append('<div id="backend-breakdown">')
    sb.append('<div class="section-title">Section 2 — Backend Bound Breakdown</div>')
    sb.append('<div class="section-subtitle">Memory subsystem vs CPU execution unit stalls</div>')

    bm  = metrics.get("Backend Memory Bound %", 0)
    bc  = metrics.get("Backend CPU Bound %", 0)
    mr  = metrics.get("Memory Stall Ratio %", 0)
    cr  = metrics.get("CPU Stall Ratio %", 0)

    rows = ""
    rows += metric_row("Total Non-Retire Events",       fmt_int(metrics.get("_Non-Retire Events", 0)))
    rows += metric_row("Load Not Complete (Mem stalls)", fmt_int(metrics.get("_Load Not Complete", 0)))
    rows += metric_row("─" * 40, "")
    rows += metric_row("Backend Bound — Memory",  fmt_pct(bm), pct_class(bm, 10, 30))
    rows += metric_row("Backend Bound — CPU",     fmt_pct(bc), pct_class(bc, 10, 25))
    rows += metric_row("  └─ Memory stall share", fmt_pct(mr))
    rows += metric_row("  └─ CPU stall share",    fmt_pct(cr))
    sb.append(table_block(rows))

    # Stacked bar for backend breakdown
    sb.append('<div class="chart-wrap">')
    sb.append('<canvas id="backendChart" style="max-height:180px;"></canvas>')
    sb.append(f"""<script>
new Chart(document.getElementById('backendChart'), {{
  type: 'bar',
  data: {{
    labels: ['Backend Bound'],
    datasets: [
      {{ label: 'Memory Bound', data: [{bm:.2f}], backgroundColor: '#1565c0' }},
      {{ label: 'CPU Bound',    data: [{bc:.2f}], backgroundColor: '#0288d1' }}
    ]
  }},
  options: {{
    indexAxis: 'y',
    plugins: {{ title: {{ display: true, text: 'Backend Breakdown (% of total slots)' }} }},
    scales: {{ x: {{ stacked: true, max: {max(be+1, 5):.1f} }}, y: {{ stacked: true }} }}
  }}
}});
</script>""")
    sb.append('</div>')
    sb.append('</div>')

    # ── Section 3: Branch Prediction ──────────────────────────────────────
    sb.append('<div id="branch-prediction">')
    sb.append('<div class="section-title">Section 3 — Branch Prediction</div>')
    sb.append('<div class="section-subtitle">'
              'AMD TAGE predictor efficiency — lower misprediction rate is better</div>')

    misp_rate = metrics.get("Branch Misprediction Rate %", 0)
    ipc       = metrics.get("IPC", 0)

    rows = ""
    rows += metric_row("Total Branches Retired",   fmt_int(metrics.get("_Total Branches", 0)))
    rows += metric_row("Branch Mispredictions",    fmt_int(metrics.get("_Branch Mispredicts", 0)))
    rows += metric_row("Instructions Retired",     fmt_int(metrics.get("_Instructions", 0)))
    rows += metric_row("CPU Cycles",               fmt_int(metrics.get("_CPU Cycles", 0)))
    rows += metric_row("─" * 40, "")
    rows += metric_row("Branch Misprediction Rate",
                       fmt_pct(misp_rate),
                       pct_class(misp_rate, 5, 15))
    rows += metric_row("Instructions Per Cycle (IPC)",
                       fmt_f(ipc),
                       "good" if ipc > 2.0 else ("warn" if ipc > 1.0 else "bad"))
    sb.append(table_block(rows))
    sb.append('</div>')

    # ── Section 4: L2 Cache ───────────────────────────────────────────────
    sb.append('<div id="l2-cache">')
    sb.append('<div class="section-title">Section 4 — L2 Cache Performance</div>')
    sb.append('<div class="section-subtitle">'
              'AMD advantage: 1 MB L2 per core (vs Intel 256–512 KB)</div>')

    dc_hr = metrics.get("L2 Data Cache Hit Rate %", 0)
    ic_hr = metrics.get("L2 Instruction Cache Hit Rate %", 0)

    rows = ""
    rows += metric_row("L2 Data Cache Hits",        fmt_int(metrics.get("_L2 DC Hits", 0)))
    rows += metric_row("L2 Data Cache Misses",       fmt_int(metrics.get("_L2 DC Misses", 0)))
    rows += metric_row("L2 Instruction Cache Hits",  fmt_int(metrics.get("_L2 IC Hits", 0)))
    rows += metric_row("L2 Instruction Cache Misses",fmt_int(metrics.get("_L2 IC Misses", 0)))
    rows += metric_row("─" * 40, "")
    rows += metric_row("L2 Data Cache Hit Rate",
                       fmt_pct(dc_hr),
                       "good" if dc_hr > 85 else ("warn" if dc_hr > 60 else "bad"))
    rows += metric_row("L2 Instruction Cache Hit Rate",
                       fmt_pct(ic_hr),
                       "good" if ic_hr > 85 else ("warn" if ic_hr > 60 else "bad"))
    sb.append(table_block(rows))

    # L2 hit-rate bar chart
    sb.append('<div class="chart-wrap">')
    sb.append('<canvas id="l2Chart" style="max-height:200px;"></canvas>')
    sb.append(f"""<script>
new Chart(document.getElementById('l2Chart'), {{
  type: 'bar',
  data: {{
    labels: ['L2 Data Cache', 'L2 Instruction Cache'],
    datasets: [
      {{ label: 'Hit Rate (%)', data: [{dc_hr:.2f},{ic_hr:.2f}],
         backgroundColor: ['#2e7d32','#1565c0'] }},
    ]
  }},
  options: {{
    plugins: {{ title: {{ display: true, text: 'L2 Cache Hit Rates (%)' }} }},
    scales: {{ y: {{ min: 0, max: 100,
                     title: {{ display: true, text: 'Hit Rate (%)' }} }} }}
  }}
}});
</script>""")
    sb.append('</div>')
    sb.append('</div>')

    # ── Insights / Interpretation ──────────────────────────────────────────
    sb.append('<div id="interpretation">')
    sb.append('<div class="section-title">Insights &amp; Optimization Guidance</div>')
    sb.append('<div class="section-subtitle">Automatically generated from your measurement results</div>')

    # Pipeline insights
    if fe > 35:
        sb.append('<div class="insight bad"><strong>High Frontend Bound ({:.1f}%)</strong>'
                  'The CPU is frequently waiting for instructions. Consider: reducing instruction '
                  'cache pressure, minimizing code size, or improving instruction locality.</div>'.format(fe))
    elif fe < 15:
        sb.append('<div class="insight good"><strong>Good Frontend Utilization ({:.1f}%)</strong>'
                  'Instruction fetch and decode are not bottlenecks.</div>'.format(fe))

    if bm > 30:
        sb.append('<div class="insight bad"><strong>High Backend Memory Bound ({:.1f}%)</strong>'
                  'Memory subsystem is a significant bottleneck. Consider: improving data locality, '
                  'reducing working set size, leveraging AMD\'s 1 MB L2 cache, and reducing '
                  'cache pressure.</div>'.format(bm))

    if bc > 25:
        sb.append('<div class="insight bad"><strong>High Backend CPU Bound ({:.1f}%)</strong>'
                  'Execution units are saturated. Consider: vectorization (AVX2/AVX-512), '
                  'algorithm optimization, or reducing computation complexity.</div>'.format(bc))

    if bs > 20:
        sb.append('<div class="insight bad"><strong>High Bad Speculation ({:.1f}%)</strong>'
                  'Many dispatched ops are not retiring. This often means high branch '
                  'misprediction or frequent pipeline flushes. See branch prediction section.</div>'.format(bs))

    if ret > 60:
        sb.append('<div class="insight good"><strong>Excellent Retiring Rate ({:.1f}%)</strong>'
                  'Most dispatch slots are doing useful work. This is the primary goal.</div>'.format(ret))
    elif ret < 30:
        sb.append('<div class="insight bad"><strong>Low Retiring Rate ({:.1f}%)</strong>'
                  'Too many slots are wasted. Focus on the highest-percentage bottleneck '
                  'category above.</div>'.format(ret))

    if misp_rate > 15:
        sb.append('<div class="insight bad"><strong>High Branch Misprediction Rate ({:.1f}%)</strong>'
                  'The branch predictor is struggling. AMD\'s TAGE predictor handles most '
                  'patterns well — high rates often indicate highly dynamic or data-dependent '
                  'branches. Consider: branch-free alternatives, sorted data, or profile-guided '
                  'optimization.</div>'.format(misp_rate))
    elif misp_rate < 5:
        sb.append('<div class="insight good"><strong>Excellent Branch Prediction ({:.1f}%)</strong>'
                  'AMD\'s TAGE predictor is handling your workload efficiently.</div>'.format(misp_rate))

    if dc_hr < 60:
        sb.append('<div class="insight bad"><strong>Low L2 Data Cache Hit Rate ({:.1f}%)</strong>'
                  'Frequent L2 misses indicate high L3/memory pressure. Optimize data access '
                  'patterns, improve locality, and consider data structure layout changes.</div>'.format(dc_hr))
    elif dc_hr > 85:
        sb.append('<div class="insight good"><strong>Excellent L2 Data Cache Hit Rate ({:.1f}%)</strong>'
                  'Your working set fits well within AMD\'s 1 MB L2 cache.</div>'.format(dc_hr))

    if ipc > 2.5:
        sb.append('<div class="insight good"><strong>Excellent IPC ({:.2f})</strong>'
                  'The CPU is executing more than 2.5 instructions per cycle — '
                  'this is very efficient for a modern out-of-order processor.</div>'.format(ipc))
    elif ipc < 1.0:
        sb.append('<div class="insight bad"><strong>Low IPC ({:.2f})</strong>'
                  'Less than 1 instruction per cycle indicates heavy stalls. '
                  'Focus on the dominant bottleneck category.</div>'.format(ipc))

    sb.append('</div>')  # interpretation

    # ── Footer ────────────────────────────────────────────────────────────
    sb.append('<div class="footer">'
              'AMD Performance Analysis Report &bull; '
              'Methodology: AMD pipeline dispatch slot analysis (6 slots/cycle) &bull; '
              'Events: AMD Zen4/Zen5 hardware performance counters via Linux perf &bull; '
              'Inspired by Intel PerfSpect HTML output format'
              '</div>')

    sb.append('</div>')  # content
    sb.append('</body></html>')
    return "\n".join(sb)


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def get_cpu_info() -> str:
    try:
        result = subprocess.run(
            ["lscpu"], capture_output=True, text=True, timeout=5
        )
        for line in result.stdout.splitlines():
            if "Model name" in line:
                return line.split(":", 1)[1].strip()
    except Exception:
        pass
    return platform.processor() or "Unknown"


def main():
    parser = argparse.ArgumentParser(
        description="AMD Performance HTML Report Generator"
    )
    parser.add_argument(
        "workload", nargs="?", default="sleep 2",
        help='Workload command to profile (default: "sleep 2")'
    )
    parser.add_argument(
        "output", nargs="?", default="amd_perf_report.html",
        help="Output HTML file (default: amd_perf_report.html)"
    )
    args = parser.parse_args()

    workload  = args.workload
    out_file  = args.output
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    cpu_info  = get_cpu_info()

    print(f"=== AMD Performance HTML Report Generator ===")
    print(f"CPU:      {cpu_info}")
    print(f"Workload: {workload}")
    print(f"Output:   {out_file}")
    print()

    all_events: dict = {}

    # ── Step 1: CPU placement / CCD topology ────────────────────────────────
    print("Collecting CPU placement & CCD topology...", end=" ", flush=True)
    placement = collect_placement_data(workload)
    if placement:
        peak = placement.get("peak_parallel_cpus", 0)
        n_ccds = placement.get("n_ccds_used", 0)
        cross  = placement.get("cross_ccd_execution", False)
        print(f"(peak={peak} CPUs, {n_ccds} CCD{'s' if n_ccds != 1 else ''}, "
              f"cross-CCD={'YES' if cross else 'NO'})")
    else:
        print("(skipped)")

    # ── Step 2: perf stat event groups ──────────────────────────────────────
    for group_name, events in EVENT_GROUPS.items():
        print(f"Collecting events: {group_name}...", end=" ", flush=True)
        group_data = collect_events(events, workload)
        all_events.update(group_data)
        collected = sum(1 for v in group_data.values() if v > 0)
        print(f"({collected}/{len(group_data.keys())} events active)")

    print()
    metrics = calculate_metrics(all_events)

    print("Key Metrics:")
    print(f"  CPU Frequency (effective): {metrics['CPU Operating Frequency (GHz)']:6.3f} GHz")
    print(f"  CPU Utilization:           {metrics['CPU Utilization %']:6.2f}%  ({metrics['CPUs Utilized (abs)']:.3f} CPUs / {metrics['_Total Cores']} total)")
    print(f"  Frontend Bound:            {metrics['Frontend Bound %']:6.2f}%")
    print(f"  Backend Bound:             {metrics['Backend Bound %']:6.2f}%")
    print(f"    └─ Memory:               {metrics['Backend Memory Bound %']:6.2f}%")
    print(f"    └─ CPU:                  {metrics['Backend CPU Bound %']:6.2f}%")
    print(f"  Bad Speculation:           {metrics['Bad Speculation %']:6.2f}%")
    print(f"  Retiring (Useful Work):    {metrics['Retiring %']:6.2f}%")
    print(f"  Branch Misprediction:      {metrics['Branch Misprediction Rate %']:6.2f}%")
    print(f"  IPC:                       {metrics['IPC']:6.2f}")
    print(f"  L2 Data Hit Rate:          {metrics['L2 Data Cache Hit Rate %']:6.2f}%")
    print()

    html_content = generate_html(metrics, workload, cpu_info, timestamp,
                                 placement=placement or None)

    with open(out_file, "w", encoding="utf-8") as f:
        f.write(html_content)

    print(f"HTML report written to: {os.path.abspath(out_file)}")
    print("Open it in any browser to view.")


if __name__ == "__main__":
    main()
