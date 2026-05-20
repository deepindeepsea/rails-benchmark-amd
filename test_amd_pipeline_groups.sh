#!/bin/bash

# AMD Pipeline Groups Testing
# Based on PerfSpect's complete AMD metric structure

set -e

echo "=== AMD Pipeline Groups Analysis ==="
echo "Testing PerfSpect's AMD metric groups on your baremetal system"
echo ""

# Function to test a specific metric group
test_metric_group() {
    local group_name="$1"
    local events="$2"
    local description="$3"

    echo "Testing Group: $group_name"
    echo "Description: $description"
    echo "Events: $events"

    if perf stat -e "$events" sleep 0.5 2>/dev/null; then
        echo "✓ $group_name events SUPPORTED"
        return 0
    else
        echo "✗ $group_name events NOT SUPPORTED"
        return 1
    fi
    echo ""
}

# Function to run comprehensive pipeline analysis
run_pipeline_analysis() {
    local workload="$1"
    echo "Running AMD pipeline analysis with workload: $workload"
    echo ""

    # Test Level 1 Pipeline Metrics (High-Level)
    echo "=== PipelineL1 (High-Level AMD Pipeline) ==="

    # These are the core pipeline events from PerfSpect
    local frontend_events="de_no_dispatch_per_slot.no_ops_from_frontend,ls_not_halted_cyc"
    local backend_events="de_no_dispatch_per_slot.backend_stalls,ls_not_halted_cyc"
    local speculation_events="de_src_op_disp.all,ex_ret_ops,resyncs_or_nc_redirects"
    local retiring_events="ex_ret_ops,ls_not_halted_cyc"

    test_metric_group "Frontend Bound" "$frontend_events" "Frontend bottlenecks (I-cache, decode)"
    test_metric_group "Backend Bound" "$backend_events" "Backend stalls (execution units, memory)"
    test_metric_group "Bad Speculation" "$speculation_events" "Mispredicts and pipeline restarts"
    test_metric_group "Retiring" "$retiring_events" "Actual useful work completed"

    # Test Level 2 Pipeline Metrics (Detailed)
    echo "=== PipelineL2 (Detailed AMD Pipeline) ==="

    local memory_bound_events="ex_no_retire.load_not_complete,ex_no_retire.not_complete"
    local mispredict_events="ex_ret_brn_misp,ex_ret_brn"

    test_metric_group "Backend Memory Bound" "$memory_bound_events" "Memory subsystem stalls"
    test_metric_group "Branch Mispredicts" "$mispredict_events" "Branch prediction efficiency"

    # Test Cache Hierarchy
    echo "=== Cache Hierarchy (AMD Advantage) ==="

    local l2_events="l2_cache_req_stat.dc_hit_in_l2,l2_cache_req_stat.ls_rd_blk_c"
    local l3_events="l3_lookup_state.all_coherent_accesses_to_l3,l3_lookup_state.l3_miss"
    local ccx_events="ls_any_fills_from_sys.local_all,ls_any_fills_from_sys.remote_cache"

    test_metric_group "L2 Cache" "$l2_events" "L2 cache efficiency"
    test_metric_group "L3 Cache" "$l3_events" "L3 cache performance"
    test_metric_group "CCX Locality" "$ccx_events" "AMD CCX locality advantage"

    # Test TLB Performance
    echo "=== TLB Performance (Virtual Memory) ==="

    local tlb_events="ls_l1_d_tlb_miss.all,ls_l2_d_tlb_hit.all"

    test_metric_group "TLB Performance" "$tlb_events" "Virtual memory efficiency"

    # Run actual performance test with supported events
    echo "=== Running Performance Test ==="

    # Always test basic events first
    echo "1. Basic CPU performance:"
    perf stat -e cpu-cycles,instructions,branches,branch-misses $workload

    echo ""
    echo "2. Testing AMD-specific branch prediction:"
    perf stat -e ex_ret_brn,ex_ret_brn_misp $workload 2>/dev/null || \
        echo "AMD branch events not supported - using generic events"

    echo ""
    echo "3. Testing AMD L2 cache analysis:"
    perf stat -e l2_cache_req_stat.dc_hit_in_l2,l2_cache_req_stat.ls_rd_blk_c $workload 2>/dev/null || \
        echo "AMD L2 events not supported - kernel may need update"

    echo ""
    echo "4. Testing AMD CCX locality (shows AMD advantage):"
    perf stat -e ls_any_fills_from_sys.local_all,ls_any_fills_from_sys.remote_cache $workload 2>/dev/null || \
        echo "AMD CCX events not supported - this is advanced functionality"

    echo ""
    echo "5. Testing AMD pipeline utilization:"
    perf stat -e de_no_dispatch_per_slot.no_ops_from_frontend,de_no_dispatch_per_slot.backend_stalls $workload 2>/dev/null || \
        echo "AMD pipeline events not supported - requires recent kernel/perf"
}

# Function to interpret results for Rails
interpret_for_rails() {
    echo "=== Rails Performance Interpretation ==="
    echo ""
    echo "AMD Pipeline Groups → Rails Performance:"
    echo ""
    echo "🎯 CRITICAL for Rails:"
    echo "  - Branch Misprediction: Ruby method dispatch efficiency"
    echo "  - Backend Memory Bound: Rails object access patterns"
    echo "  - CCX Locality: AMD's cache hierarchy advantage"
    echo "  - L2 Cache Efficiency: Rails object caching"
    echo ""
    echo "📊 IMPORTANT for Rails:"
    echo "  - Frontend Bound: Ruby method compilation overhead"
    echo "  - Retiring Fastpath: Efficient Rails operations"
    echo "  - TLB Performance: Ruby heap virtual memory"
    echo ""
    echo "🔧 OPTIMIZATION TARGETS:"
    echo "  - Minimize branch mispredicts (better method dispatch)"
    echo "  - Maximize CCX locality (keep objects in same CCX)"
    echo "  - Optimize L2 hit rates (better object caching)"
    echo "  - Reduce TLB misses (efficient Ruby heap layout)"
    echo ""
    echo "📈 AMD ADVANTAGES for Rails:"
    echo "  - 1MB L2 cache per core (vs Intel 256-512KB)"
    echo "  - CCX locality metrics (unique to AMD)"
    echo "  - Superior branch predictor for dynamic dispatch"
    echo "  - Better NUMA topology (Data Fabric)"
}

# Main execution
echo "This tests which AMD pipeline metrics work on your system"
echo "and shows how they map to Rails performance optimization"
echo ""

# Create a simple test workload
WORKLOAD="dd if=/dev/zero of=/tmp/pipeline_test bs=1M count=50 2>/dev/null; rm -f /tmp/pipeline_test"

# Run the comprehensive analysis
run_pipeline_analysis "$WORKLOAD"

# Provide Rails-specific interpretation
interpret_for_rails

echo ""
echo "=== Summary ==="
echo "✓ Events that work can be used for Rails performance analysis"
echo "✗ Events that don't work need kernel/perf updates or aren't available"
echo ""
echo "This creates the foundation for a workload-agnostic AMD performance toolkit"
echo "that can analyze Rails, databases, ML workloads, or any application using"
echo "AMD's proper pipeline methodology (not Intel's TopDown)."
echo ""
echo "Next: Integrate working events into automated Rails benchmark analysis!"