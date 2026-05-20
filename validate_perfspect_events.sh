#!/bin/bash

# PerfSpect Event Validation Script
# Tests key AMD performance events and metrics on baremetal system

set -e

echo "=== PerfSpect AMD Event Validation ==="
echo "Testing on: $(hostname)"
echo "CPU: $(lscpu | grep 'Model name' | cut -d: -f2 | xargs)"
echo "Date: $(date)"
echo ""

# Test basic core events first
echo "1. Testing Basic Core Events..."
perf stat -e cpu-cycles,instructions,ex_ret_brn,ex_ret_brn_misp sleep 1 || echo "Basic events failed"
echo ""

# Test pipeline utilization events (complex PerfSpect metrics)
echo "2. Testing Pipeline Utilization Events..."
echo "Frontend Bound events:"
perf stat -e de_no_dispatch_per_slot.no_ops_from_frontend,ls_not_halted_cyc sleep 1 2>&1 | head -10 || echo "Frontend events not available"

echo "Backend Bound events:"
perf stat -e de_no_dispatch_per_slot.backend_stalls sleep 1 2>&1 | head -10 || echo "Backend events not available"

echo "Bad Speculation events:"
perf stat -e de_src_op_disp.all,ex_ret_ops,resyncs_or_nc_redirects sleep 1 2>&1 | head -10 || echo "Speculation events not available"
echo ""

# Test L2 cache events (critical for Rails)
echo "3. Testing L2 Cache Events..."
perf stat -e l2_cache_req_stat.dc_hit_in_l2,l2_cache_req_stat.ic_dc_miss_in_l2,l2_request_g1.all_dc sleep 1 2>&1 | head -10 || echo "L2 cache events not available"
echo ""

# Test L3 cache events
echo "4. Testing L3 Cache Events..."
perf stat -e l3_lookup_state.all_coherent_accesses_to_l3,l3_lookup_state.l3_miss,l3_lookup_state.l3_hit sleep 1 2>&1 | head -10 || echo "L3 cache events not available"
echo ""

# Test CCX locality events (AMD-specific advantage)
echo "5. Testing CCX Locality Events..."
perf stat -e ls_any_fills_from_sys.local_all,ls_any_fills_from_sys.remote_cache,ls_any_fills_from_sys.dram_io_all sleep 1 2>&1 | head -10 || echo "CCX locality events not available"
echo ""

# Test TLB events
echo "6. Testing TLB Events..."
perf stat -e ls_l1_d_tlb_miss.all,ls_l2_d_tlb_hit.all,ls_l1_d_tlb_miss.all_l2_miss sleep 1 2>&1 | head -10 || echo "TLB events not available"
echo ""

# Test Data Fabric events (memory bandwidth)
echo "7. Testing Data Fabric Events..."
perf stat -e local_processor_read_data_beats_cs0,local_processor_write_data_beats_cs0 sleep 1 2>&1 | head -10 || echo "Data Fabric events not available"
echo ""

# Test with actual workload (short stress test)
echo "8. Testing with Real Workload (stress test)..."
echo "Running 5-second CPU stress to generate meaningful event counts..."

# Generate some CPU activity
perf stat -e cpu-cycles,instructions,ex_ret_brn_misp,ex_ret_brn,\
l2_cache_req_stat.dc_hit_in_l2,l2_cache_req_stat.ls_rd_blk_c,\
ls_any_fills_from_sys.local_all,ls_l1_d_tlb_miss.all \
dd if=/dev/zero of=/tmp/test bs=1M count=100 2>/dev/null

rm -f /tmp/test
echo ""

# Calculate some basic metrics manually
echo "9. Manual Metric Calculation Test..."
echo "Running perf with JSON output for easier parsing..."

perf stat -j -e cpu-cycles,instructions,ex_ret_brn_misp,ex_ret_brn \
dd if=/dev/zero of=/tmp/test bs=1M count=50 2>/tmp/perf_output.json >/dev/null

if [ -f /tmp/perf_output.json ]; then
    echo "Sample perf JSON output:"
    cat /tmp/perf_output.json | head -20

    # Try to extract and calculate basic metrics
    echo ""
    echo "Attempting basic metric calculation..."
    echo "(This would need proper JSON parsing in a real implementation)"
fi

rm -f /tmp/test /tmp/perf_output.json
echo ""

echo "=== Validation Complete ==="
echo "Check the output above to see which events work on your system."
echo "Events that show 'not supported' or 'not available' need alternative approaches."
echo ""
echo "Key events to confirm for Rails analysis:"
echo "- Branch prediction: ex_ret_brn_misp, ex_ret_brn"
echo "- L2 cache: l2_cache_req_stat.dc_hit_in_l2, l2_cache_req_stat.ls_rd_blk_c"
echo "- CCX locality: ls_any_fills_from_sys.local_all, ls_any_fills_from_sys.remote_cache"
echo "- TLB: ls_l1_d_tlb_miss.all"
echo ""
echo "Pipeline utilization events are more complex and may need kernel support."