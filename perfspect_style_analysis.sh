#!/bin/bash

# PerfSpect-Style AMD Pipeline Analysis
# Based on Intel PerfSpect's approach for collecting AMD metrics

set -e

echo "=== PerfSpect-Style AMD Performance Analysis ==="
echo "CPU: $(lscpu | grep 'Model name' | cut -d: -f2 | xargs)"
echo "Architecture: $(lscpu | grep Architecture | awk '{print $2}')"
echo ""

# Function to check if events are supported
check_events_supported() {
    local events="$1"
    echo "Testing event support: $events"

    if perf stat -e "$events" sleep 0.1 2>/dev/null; then
        echo "✓ Events supported"
        return 0
    else
        echo "✗ Events not supported"
        return 1
    fi
}

# Function to run performance analysis with PerfSpect-style approach
run_perfspect_analysis() {
    local workload_cmd="$1"
    local output_file="$2"

    echo "Running PerfSpect-style analysis..."
    echo "Workload: $workload_cmd"
    echo "Output: $output_file"
    echo ""

    # Core metrics that should work on any AMD system
    local basic_events="cpu-cycles,instructions,branches,branch-misses,L1-dcache-loads,L1-dcache-load-misses"

    # AMD-specific events from PerfSpect Genoa metrics
    local amd_branch_events="ex_ret_brn,ex_ret_brn_misp"
    local amd_cache_events="l2_cache_req_stat.dc_hit_in_l2,l2_cache_req_stat.ls_rd_blk_c"
    local amd_ccx_events="ls_any_fills_from_sys.local_all,ls_any_fills_from_sys.remote_cache"
    local amd_tlb_events="ls_l1_d_tlb_miss.all,ls_l2_d_tlb_hit.all"
    local amd_pipeline_events="de_no_dispatch_per_slot.no_ops_from_frontend,de_no_dispatch_per_slot.backend_stalls,de_src_op_disp.all,ex_ret_ops"

    # Try different event combinations based on what's supported
    echo "1. Testing basic events (should work everywhere)..."
    if check_events_supported "$basic_events"; then
        perf stat -e "$basic_events" -o "${output_file}_basic.txt" $workload_cmd 2>&1
        echo "Basic metrics saved to ${output_file}_basic.txt"
    fi
    echo ""

    echo "2. Testing AMD branch prediction events..."
    if check_events_supported "$amd_branch_events"; then
        perf stat -e "$amd_branch_events" -o "${output_file}_branch.txt" $workload_cmd 2>&1
        echo "AMD branch metrics saved to ${output_file}_branch.txt"
    else
        echo "Fallback to basic branch events"
        perf stat -e "branches,branch-misses" -o "${output_file}_branch_basic.txt" $workload_cmd 2>&1
    fi
    echo ""

    echo "3. Testing AMD L2 cache events..."
    if check_events_supported "$amd_cache_events"; then
        perf stat -e "$amd_cache_events" -o "${output_file}_cache.txt" $workload_cmd 2>&1
        echo "AMD cache metrics saved to ${output_file}_cache.txt"
    else
        echo "Fallback to basic cache events"
        perf stat -e "cache-references,cache-misses" -o "${output_file}_cache_basic.txt" $workload_cmd 2>&1
    fi
    echo ""

    echo "4. Testing AMD CCX locality events..."
    if check_events_supported "$amd_ccx_events"; then
        perf stat -e "$amd_ccx_events" -o "${output_file}_ccx.txt" $workload_cmd 2>&1
        echo "AMD CCX locality metrics saved to ${output_file}_ccx.txt"
    else
        echo "CCX events not supported on this system"
    fi
    echo ""

    echo "5. Testing AMD TLB events..."
    if check_events_supported "$amd_tlb_events"; then
        perf stat -e "$amd_tlb_events" -o "${output_file}_tlb.txt" $workload_cmd 2>&1
        echo "AMD TLB metrics saved to ${output_file}_tlb.txt"
    else
        echo "TLB events not supported on this system"
    fi
    echo ""

    echo "6. Testing AMD pipeline utilization events..."
    if check_events_supported "$amd_pipeline_events"; then
        perf stat -e "$amd_pipeline_events" -o "${output_file}_pipeline.txt" $workload_cmd 2>&1
        echo "AMD pipeline metrics saved to ${output_file}_pipeline.txt"
    else
        echo "Pipeline events not supported - this is expected on older kernels"
    fi
    echo ""
}

# Function to calculate metrics from collected data (simplified version)
calculate_metrics() {
    echo "=== Calculating PerfSpect-style metrics ==="

    for file in /tmp/perfspect_*.txt; do
        if [ -f "$file" ]; then
            echo ""
            echo "Analyzing: $(basename $file)"

            # Extract key values and calculate basic metrics
            if grep -q "instructions" "$file"; then
                instructions=$(grep "instructions" "$file" | awk '{print $1}' | tr -d ',')
                cycles=$(grep "cycles" "$file" | awk '{print $1}' | tr -d ',')

                if [ -n "$instructions" ] && [ -n "$cycles" ]; then
                    # Calculate IPC using bc if available, otherwise skip
                    if command -v bc > /dev/null; then
                        ipc=$(echo "scale=2; $instructions / $cycles" | bc)
                        echo "  IPC (Instructions per Cycle): $ipc"
                    fi
                fi
            fi

            if grep -q "branch-misses\|ex_ret_brn_misp" "$file"; then
                echo "  Branch prediction metrics available"
            fi

            if grep -q "cache-misses\|l2_cache_req_stat" "$file"; then
                echo "  Cache hierarchy metrics available"
            fi

            if grep -q "ls_any_fills_from_sys" "$file"; then
                echo "  CCX locality metrics available (AMD-specific advantage)"
            fi
        fi
    done
}

# Main execution
echo "Creating test workload..."
# Use a simple but meaningful workload for testing
WORKLOAD="dd if=/dev/zero of=/tmp/test bs=1M count=100 2>/dev/null; rm -f /tmp/test"

# Run the analysis
run_perfspect_analysis "$WORKLOAD" "/tmp/perfspect"

# Calculate and display metrics
calculate_metrics

echo ""
echo "=== Summary ==="
echo "PerfSpect-style analysis complete!"
echo "This approach:"
echo "1. Tests event support before using them (like PerfSpect does)"
echo "2. Falls back to basic events when AMD-specific ones aren't available"
echo "3. Collects data using the same event combinations as PerfSpect"
echo "4. Can be extended with the JSON formula calculations from genoa.json"
echo ""
echo "Next steps:"
echo "- Integrate the actual PerfSpect formulas from genoa.json"
echo "- Add proper JSON parsing for automated metric calculation"
echo "- Extend for Rails-specific workload analysis"
echo ""
echo "Output files:"
ls -la /tmp/perfspect_*.txt 2>/dev/null || echo "No output files generated"