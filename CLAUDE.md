# rails-benchmark-amd — CLAUDE.md

Project context for AI agents. Read this before touching any file in this repo.

## What This Project Is

Ruby on Rails benchmarking application optimized for AMD EPYC hardware. Measures
Rails request throughput, latency, and database performance while correlating with
AMD CPU hardware performance counters (pipeline utilization, cache, branch prediction).

Primary goal: understand how Rails workloads behave on AMD Zen4/Zen5 vs Intel —
pipeline bottlenecks, memory-bound vs CPU-bound characteristics, L2/L3 cache usage.

## Hardware Target

- **Primary test machine**: AMD EPYC 9684X, 96 cores, 12 CCDs, Zen4 (Genoa)
- **Also tested**: AMD EPYC Zen5 (Turin) on EC2 M8A
- **OS**: Ubuntu 22.04, bare-metal or EC2

## Application Stack

- Ruby 3.2.0
- Rails 7.1
- SQLite3 (default dev/bench database)
- Puma web server
- Port: 3000 (default)

## Key Files

| File | Purpose |
|------|---------|
| `amd_pipeline_metrics.sh` | AMD perf terminal report (wrap any workload) |
| `amd_perf_html_report.py` | PerfSpect-style HTML report |
| `amd_perf_excel_report.py` | Netflix PerfSpect Excel format |
| `amd_cpu_placement.py` | CCD topology + core placement monitor |
| `rails_amd_pipeline_analysis.sh` | Rails-specific pipeline analysis script |
| `benchmark_detailed.sh` | Detailed Rails benchmark runner |
| `analyze_performance.sh` | Performance analysis wrapper |
| `setup_ubuntu.sh` | Ubuntu environment setup for AMD perf tools |
| `test_amd_pipeline_baremetal.sh` | Bare-metal perf event validation |

> **Note:** The core AMD perf scripts (amd_pipeline_metrics.sh, amd_perf_html_report.py,
> amd_perf_excel_report.py, amd_cpu_placement.py) now have a canonical home at:
> `C:\Users\pradeepn\amd-perf-toolkit\amd-perf-toolkit\`
> Changes to these scripts should be made there and synced here.

## Running the Rails App

```bash
bundle install
rails db:create db:migrate db:seed
rails server -p 3000

# Run benchmark while server is running
ab -n 1000 -c 10 http://localhost:3000/
wrk -t4 -c100 -d30s http://localhost:3000/
```

## Running AMD Perf Analysis Against Rails

```bash
# Profile a single Rails request / short workload
./amd_pipeline_metrics.sh "ab -n 500 -c 5 http://localhost:3000/"

# HTML report
python3 amd_perf_html_report.py "ab -n 500 -c 5 http://localhost:3000/" rails_report.html

# CCD placement — see if Rails threads spread across chiplets
python3 amd_cpu_placement.py -- ab -n 500 -c 5 http://localhost:3000/
```

## AMD Hardware Facts (Do Not Change)

- Dispatch model: **6 slots per cycle** (not Intel 4-wide TopDown)
- L2: 1 MB per core (Zen4) — much larger than Intel
- Each CCD: 8 cores sharing 32 MB L3; cross-CCD = separate L3 domains
- EPYC 9684X: 12 CCDs × 8 cores = 96 cores
- Cross-CCD execution introduces ~100 ns cache-to-cache latency

## Confirmed Working perf Events on This System

```
de_no_dispatch_per_slot.no_ops_from_frontend
de_no_dispatch_per_slot.backend_stalls
de_src_op_disp.all / ex_ret_ops / ls_not_halted_cyc
ex_no_retire.load_not_complete / ex_no_retire.not_complete
ex_ret_brn_misp / ex_ret_brn
l2_cache_req_stat.dc_hit_in_l2 / ls_rd_blk_c / ic_fill_miss / ic_hit_in_l2
task-clock / cpu-cycles / instructions
```

## Events That Do NOT Work on This System

```
l3_lookup_state.*    # confirmed broken on EPYC 9684X — do not use
```

## perf Requirements

```bash
sudo sysctl -w kernel.perf_event_paranoid=1   # required for hardware events
```

## Docker

`Dockerfile` and `docker-compose.yml` are present but perf hardware events do NOT
work inside Docker containers (no PMU access). Use bare-metal or EC2 directly for
any perf stat based profiling.
