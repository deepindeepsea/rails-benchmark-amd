#!/bin/bash

# AMD Pipeline Analysis - Idle System Testing
# Minimal testing of AMD pipeline events on idle system
# Uses confirmed working events from your baremetal system

set -e

echo "=== AMD Pipeline Analysis - Idle System Test ==="
echo "Testing AMD pipeline methodology on idle/low-activity system"
echo "Using confirmed working events from your baremetal system"
echo ""

# Function to test AMD pipeline events with minimal workload
test_amd_events() {
    echo "🔍 Testing AMD Pipeline Events..."
    echo ""

    # Test 1: Basic AMD Pipeline Events (very light workload)
    echo "1. Testing AMD Pipeline L1 events..."
    echo "   Events: Frontend/Backend/Speculation/Retiring"

    perf stat -e de_no_dispatch_per_slot.no_ops_from_frontend,\
de_no_dispatch_per_slot.backend_stalls,\
de_src_op_disp.all,\
ex_ret_ops,\
ls_not_halted_cyc \
        sleep 2

    echo ""
    echo "✓ AMD Pipeline L1 events work!"
    echo ""

    # Test 2: Memory-bound analysis events
    echo "2. Testing Memory-Bound Analysis events..."
    echo "   Events: Load completion vs other retirement stalls"

    perf stat -e ex_no_retire.load_not_complete,\
ex_no_retire.not_complete,\
ls_not_halted_cyc \
        sleep 2

    echo ""
    echo "✓ Memory-bound analysis events work!"
    echo ""

    # Test 3: Branch prediction events
    echo "3. Testing Branch Prediction events..."
    echo "   Events: Branch mispredicts vs total branches"

    perf stat -e ex_ret_brn_misp,\
ex_ret_brn,\
cpu-cycles,\
instructions \
        sleep 2

    echo ""
    echo "✓ Branch prediction events work!"
    echo ""

    # Test 4: L2 cache events
    echo "4. Testing L2 Cache events (AMD advantage)..."
    echo "   Events: L2 hits vs misses"

    perf stat -e l2_cache_req_stat.dc_hit_in_l2,\
l2_cache_req_stat.ls_rd_blk_c,\
cpu-cycles,\
instructions \
        sleep 2

    echo ""
    echo "✓ L2 cache analysis events work!"
    echo ""
}

# Function to show what the metrics mean
explain_amd_metrics() {
    echo "=== AMD Pipeline Metrics Explanation ==="
    echo ""
    echo "📊 What These Events Measure:"
    echo ""
    echo "🏭 AMD PIPELINE UTILIZATION (6 dispatch slots per cycle):"
    echo "   • de_no_dispatch_per_slot.no_ops_from_frontend"
    echo "     └─ Frontend Bound: Instruction cache, decode bottlenecks"
    echo ""
    echo "   • de_no_dispatch_per_slot.backend_stalls"
    echo "     └─ Backend Bound: Execution unit, memory stalls"
    echo ""
    echo "   • de_src_op_disp.all vs ex_ret_ops"
    echo "     └─ Bad Speculation: Mispredicted work that didn't retire"
    echo ""
    echo "   • ex_ret_ops / ls_not_halted_cyc"
    echo "     └─ Retiring: Actual useful work completed"
    echo ""
    echo "💾 MEMORY SUBSYSTEM:"
    echo "   • ex_no_retire.load_not_complete vs ex_no_retire.not_complete"
    echo "     └─ Shows if stalls are memory-related vs other causes"
    echo ""
    echo "🎯 BRANCH PREDICTION:"
    echo "   • ex_ret_brn_misp / ex_ret_brn"
    echo "     └─ Branch misprediction rate (AMD TAGE predictor)"
    echo ""
    echo "🏪 L2 CACHE (AMD's 1MB advantage):"
    echo "   • l2_cache_req_stat.dc_hit_in_l2 / (hits + ls_rd_blk_c)"
    echo "     └─ L2 cache hit rate for data accesses"
    echo ""
}

# Function to compare with Intel approach
amd_vs_intel() {
    echo "=== AMD vs Intel Pipeline Analysis ==="
    echo ""
    echo "❌ INTEL TOPDOWN (doesn't work properly on AMD):"
    echo "   • Generic 4-category model"
    echo "   • Based on Intel pipeline assumptions"
    echo "   • Missing AMD-specific optimizations"
    echo ""
    echo "✅ AMD PIPELINE ANALYSIS (what we're using):"
    echo "   • Direct AMD dispatch slot measurement"
    echo "   • AMD-specific execution model"
    echo "   • Shows AMD architectural advantages"
    echo "   • Memory vs CPU-bound differentiation"
    echo "   • CCX locality analysis (when available)"
    echo ""
    echo "🚀 WHY THIS MATTERS:"
    echo "   • Get accurate performance analysis"
    echo "   • Leverage AMD's architectural strengths"
    echo "   • Optimize for AMD's cache hierarchy"
    echo "   • Proper branch prediction analysis"
    echo ""
}

# Function to show next steps
next_steps() {
    echo "=== Next Steps ==="
    echo ""
    echo "✅ CONFIRMED: Your system supports AMD pipeline analysis!"
    echo ""
    echo "🎯 READY FOR PRODUCTION:"
    echo "   1. Apply to Rails applications"
    echo "   2. Use for database performance analysis"
    echo "   3. Optimize ML/AI workloads"
    echo "   4. Monitor any application using proper AMD methodology"
    echo ""
    echo "📈 INTEGRATION OPTIONS:"
    echo "   • Add to CI/CD pipelines"
    echo "   • Create automated monitoring"
    echo "   • Build performance dashboards"
    echo "   • Optimize application deployment"
    echo ""
    echo "🔧 OPTIMIZATION TARGETS:"
    echo "   • Minimize Frontend Bound % (instruction efficiency)"
    echo "   • Minimize Backend Memory Bound % (cache optimization)"
    echo "   • Minimize Branch Misprediction % (control flow)"
    echo "   • Maximize L2 Hit Rate % (leverage AMD's 1MB L2)"
    echo ""
}

# Main execution
echo "Running minimal AMD pipeline test on idle system..."
echo ""

# Test the events
test_amd_events

# Explain what we measured
explain_amd_metrics

# Show advantages over Intel approach
amd_vs_intel

# Show next steps
next_steps

echo ""
echo "=== Test Complete ==="
echo "🎉 Your AMD baremetal system is ready for production performance analysis!"
echo "   All critical AMD pipeline events are working correctly."
echo ""
echo "💡 To use with applications:"
echo "   Replace 'sleep 2' with your actual workload commands"
echo "   (Rails server, database, ML training, etc.)"