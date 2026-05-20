#!/bin/bash

# Performance Analysis Script for Rails Benchmark
# Compares AMD vs Intel vs ARM microarchitectural performance

set -e

APP_URL="${1:-http://localhost:3000}"
RESULTS_DIR="/home/ubuntu/perf-analysis"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null || echo "unknown")

mkdir -p $RESULTS_DIR

echo "=== Performance Analysis for $INSTANCE_TYPE ==="
echo "Target: $APP_URL"
echo "Results: $RESULTS_DIR"

# Detect CPU architecture
CPU_VENDOR=$(lscpu | grep "Vendor ID" | awk '{print $3}')
CPU_MODEL=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)

echo "CPU: $CPU_VENDOR - $CPU_MODEL"

# Function to run perf analysis
run_perf_analysis() {
    local endpoint="$1"
    local test_name="$2"
    local duration="$3"

    echo "Running $test_name analysis..."

    # Basic performance counters
    perf stat -e cycles,instructions,cache-references,cache-misses,branches,branch-misses \
        -o "$RESULTS_DIR/${test_name}_basic_${TIMESTAMP}.txt" \
        wrk -t8 -c200 -d${duration}s "$APP_URL$endpoint" 2>&1 | \
        tee "$RESULTS_DIR/${test_name}_wrk_${TIMESTAMP}.txt"

    # Advanced microarchitectural analysis
    if [[ "$CPU_VENDOR" == "AuthenticAMD" ]]; then
        # AMD-specific counters using OFFICIAL EVENT CODES from Table 26
        echo "Running AMD-specific analysis with official event codes..."
        perf stat -e r4300C0,r4300C1,r4300C2,r4300C3,r430729,r43E860,r43F064,r430864 \
            -o "$RESULTS_DIR/${test_name}_amd_detailed_${TIMESTAMP}.txt" \
            wrk -t8 -c200 -d${duration}s "$APP_URL$endpoint"

        # AMD L2 cache analysis using OFFICIAL TABLE 26 FORMULAS
        echo "Running AMD L2 cache analysis (Table 26 formulas)..."
        perf stat -e r43F960,r431F70,r431F71,r431F72,r430664,r43F064,r430164,r430864 \
            -o "$RESULTS_DIR/${test_name}_amd_l2_${TIMESTAMP}.txt" \
            wrk -t8 -c200 -d${duration}s "$APP_URL$endpoint" 2>/dev/null || echo "L2 PMC events not available"

        # AMD L3 cache analysis using CONFIRMED WORKING events
        echo "Running AMD L3 cache analysis..."
        perf stat -e l3_cache_accesses,l3_misses,l3_read_miss_latency \
            -o "$RESULTS_DIR/${test_name}_amd_l3_${TIMESTAMP}.txt" \
            wrk -t8 -c200 -d${duration}s "$APP_URL$endpoint" 2>/dev/null || echo "L3 events not available"

        # AMD TLB analysis using OFFICIAL TABLE 26 FORMULAS
        echo "Running AMD TLB analysis (Table 26 formulas)..."
        perf stat -e r430084,r430785,r43FF45,r43F045,r43FF78 \
            -o "$RESULTS_DIR/${test_name}_amd_tlb_${TIMESTAMP}.txt" \
            wrk -t8 -c200 -d${duration}s "$APP_URL$endpoint" 2>/dev/null || echo "TLB PMC events not available"

        # AMD Advanced Caching analysis using OFFICIAL TABLE 26 FORMULAS
        echo "Running AMD advanced caching analysis (Table 26 formulas)..."
        perf stat -e r434844,r435044,r430344,r431444,r43FF44 \
            -o "$RESULTS_DIR/${test_name}_amd_dcfill_${TIMESTAMP}.txt" \
            wrk -t8 -c200 -d${duration}s "$APP_URL$endpoint" 2>/dev/null || echo "Data cache fill events not available"

        # AMD Floating-Point analysis using PMCx003
        echo "Running AMD floating-point analysis (PMCx003)..."
        perf stat -e fp_ret_sse_avx_ops.add_sub_flops,fp_ret_sse_avx_ops.mult_flops,\
fp_ret_sse_avx_ops.div_flops,fp_ret_sse_avx_ops.mac_flops \
            -o "$RESULTS_DIR/${test_name}_amd_fp_${TIMESTAMP}.txt" \
            wrk -t8 -c200 -d${duration}s "$APP_URL$endpoint" 2>/dev/null || echo "Floating-point events not available"

        # AMD Comprehensive cache analysis using GROUPED events
        echo "Running AMD comprehensive cache analysis..."
        perf stat -e all_l2_cache_accesses,all_l2_cache_hits,all_l2_cache_misses \
            -o "$RESULTS_DIR/${test_name}_amd_cache_comprehensive_${TIMESTAMP}.txt" \
            wrk -t8 -c200 -d${duration}s "$APP_URL$endpoint" 2>/dev/null || echo "Comprehensive cache events not available"

    elif [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then
        # Intel-specific counters
        echo "Running Intel-specific analysis..."
        perf stat -e cycles,instructions,L1-dcache-loads,L1-dcache-load-misses,\
L1-icache-load-misses,LLC-loads,LLC-load-misses,\
branch-loads,branch-load-misses,mem_load_retired.l3_miss \
            -o "$RESULTS_DIR/${test_name}_intel_detailed_${TIMESTAMP}.txt" \
            wrk -t8 -c200 -d${duration}s "$APP_URL$endpoint"

    elif [[ "$CPU_MODEL" == *"ARM"* ]] || [[ "$CPU_MODEL" == *"Graviton"* ]]; then
        # ARM-specific counters
        echo "Running ARM-specific analysis..."
        perf stat -e cycles,instructions,L1-dcache-loads,L1-dcache-load-misses,\
L1-icache-load-misses,LL-loads,LL-load-misses,\
branch-loads,branch-load-misses \
            -o "$RESULTS_DIR/${test_name}_arm_detailed_${TIMESTAMP}.txt" \
            wrk -t8 -c200 -d${duration}s "$APP_URL$endpoint"
    fi

    # Memory and TLB analysis
    perf stat -e dTLB-loads,dTLB-load-misses,iTLB-loads,iTLB-load-misses,\
node-loads,node-load-misses,node-stores,node-store-misses \
        -o "$RESULTS_DIR/${test_name}_memory_${TIMESTAMP}.txt" \
        wrk -t8 -c200 -d${duration}s "$APP_URL$endpoint" 2>/dev/null || \
        echo "Some memory counters not available on this platform"
}

# Function to run perfspect analysis (if available)
run_perfspect_analysis() {
    local endpoint="$1"
    local test_name="$2"

    if command -v perfspect &> /dev/null; then
        echo "Running perfspect analysis for $test_name..."

        # Start perfspect collection
        perfspect -p $(pgrep -f puma) -t 30 -o "$RESULTS_DIR/${test_name}_perfspect_${TIMESTAMP}" &
        PERFSPECT_PID=$!

        # Run workload
        wrk -t8 -c200 -d30s "$APP_URL$endpoint" > "$RESULTS_DIR/${test_name}_perfspect_wrk_${TIMESTAMP}.txt"

        # Wait for perfspect to complete
        wait $PERFSPECT_PID

        echo "Perfspect analysis complete for $test_name"
    else
        echo "perfspect not available, skipping advanced analysis"
    fi
}

# Function to profile with detailed event sampling
run_detailed_profiling() {
    local endpoint="$1"
    local test_name="$2"

    echo "Running detailed CPU profiling for $test_name..."

    # Record detailed execution profile
    perf record -g -F 999 -o "$RESULTS_DIR/${test_name}_profile_${TIMESTAMP}.data" \
        wrk -t4 -c100 -d15s "$APP_URL$endpoint" &

    PERF_PID=$!
    sleep 20  # Let it run
    kill $PERF_PID 2>/dev/null || true

    # Generate report
    perf report -i "$RESULTS_DIR/${test_name}_profile_${TIMESTAMP}.data" \
        > "$RESULTS_DIR/${test_name}_profile_report_${TIMESTAMP}.txt"
}

# Function to calculate official AMD performance ratios from Table 26
calculate_amd_ratios() {
    local results_file="$1"
    local output_file="$2"

    echo "Calculating AMD official performance ratios from Table 26..."

    cat > "$output_file" << 'EOF'
# AMD Official Performance Ratios Calculator
# Based on Table 26: Guidance for Common Performance Statistics

# This script processes perf stat output and calculates official AMD ratios
# Usage: Run this after collecting perf data with official event codes

echo "=== AMD OFFICIAL PERFORMANCE STATISTICS ==="
echo "Based on Table 26 from AMD Family 19h documentation"
echo ""

# Extract values from perf stat results (you'll need to parse actual output)
echo "1. BRANCH PREDICTION:"
echo "   - Execution-Time Branch Misprediction Ratio = Event[0x4300C3] / Event[0x4300C2]"
echo "   - Target: <10% for optimized Rails applications"
echo ""

echo "2. BASIC CACHING:"
echo "   - All Data Cache Accesses = Event[0x430729]"
echo "   - All L2 Cache Accesses = Event[0x43F960] + Event[0x431F70] + Event[0x431F71] + Event[0x431F72]"
echo "   - L2 Cache Hit from L1 Data Cache Miss = Event[0x43F064]"
echo "   - L2 Cache Miss from L1 Data Cache Miss = Event[0x430864]"
echo "   - L2 Hit Ratio = Event[0x43F064] / (Event[0x43F064] + Event[0x430864])"
echo "   - Target: >85% L2 hit ratio for Rails object access"
echo ""

echo "3. ADVANCED CACHING:"
echo "   - L1 Data Cache Fills from Memory = Event[0x434844]"
echo "   - L1 Data Cache Fills from within same CCX = Event[0x430344]"
echo "   - L1 Data Cache Fills from another CCX cache = Event[0x431444]"
echo "   - L1 Data Cache Fills All = Event[0x43FF44]"
echo "   - CCX Locality Ratio = Event[0x430344] / (Event[0x430344] + Event[0x431444])"
echo "   - Memory Pressure = Event[0x434844] / Event[0x43FF44]"
echo "   - Target: >80% CCX locality, <15% memory pressure for Rails"
echo ""

echo "4. TLB PERFORMANCE:"
echo "   - L1 DTLB Misses = Event[0x43FF45]"
echo "   - L2 DTLB Misses & Data page walk = Event[0x43F045]"
echo "   - TLB Miss Rate = Event[0x43FF45] / Event[0x430729]"
echo "   - Page Walk Rate = Event[0x43F045] / Event[0x430729]"
echo "   - Target: <1% TLB miss rate, <0.1% page walk rate for Rails"
echo ""

echo "5. CORE EFFICIENCY:"
echo "   - Instructions Per Cycle (IPC) = Event[0x4300C0] / Event[0x4300C1]"
echo "   - Target: >1.5 IPC for efficient Rails applications"
echo ""

echo "NOTE: Parse actual perf stat output to calculate these ratios with real values"
EOF

    chmod +x "$output_file"
    echo "Ratio calculation template created at: $output_file"
}

# Function to run Rails-specific workload analysis using official PMC registers
analyze_rails_workloads() {
    local endpoint="$1"
    local test_name="$2"
    local duration="$3"

    echo "Running Rails-optimized PMC analysis for $test_name..."

    if [[ "$endpoint" == "/json" ]]; then
        # JSON serialization workload - focus on object traversal using TABLE 26 EVENTS
        echo "JSON serialization analysis using official AMD Table 26 events..."
        perf stat -e r4300C0,r4300C1,r4300C2,r4300C3,r43F064,r430864,r430344,r431444 \
            -o "$RESULTS_DIR/${test_name}_json_pmc_${TIMESTAMP}.txt" \
            wrk -t8 -c200 -d${duration}s "$APP_URL$endpoint" 2>/dev/null || echo "JSON PMC events not available"

    elif [[ "$endpoint" == "/data" ]]; then
        # Data processing workload - focus on memory hierarchy using TABLE 26 EVENTS
        echo "Data processing analysis using official AMD Table 26 events..."
        perf stat -e r4300C0,r4300C1,r4300C2,r4300C3,r434844,r43FF44,r430344,r431444 \
            -o "$RESULTS_DIR/${test_name}_data_pmc_${TIMESTAMP}.txt" \
            wrk -t8 -c200 -d${duration}s "$APP_URL$endpoint" 2>/dev/null || echo "Data PMC events not available"

    elif [[ "$endpoint" == "/hello" ]]; then
        # Simple endpoint - focus on core efficiency using TABLE 26 EVENTS
        echo "Simple endpoint analysis using official AMD Table 26 events..."
        perf stat -e r4300C0,r4300C1,r4300C2,r4300C3,r43FF45,r43F045 \
            -o "$RESULTS_DIR/${test_name}_hello_pmc_${TIMESTAMP}.txt" \
            wrk -t8 -c200 -d${duration}s "$APP_URL$endpoint" 2>/dev/null || echo "Hello PMC events not available"
    fi

    # Calculate official AMD ratios using Table 26 formulas
    calculate_amd_ratios "$RESULTS_DIR/${test_name}_*_pmc_${TIMESTAMP}.txt" \
                        "$RESULTS_DIR/${test_name}_amd_ratios_${TIMESTAMP}.sh"

    # Calculate key performance ratios based on PMC register data
    echo "Calculating AMD PMC performance ratios..."
    cat > "$RESULTS_DIR/${test_name}_pmc_ratios_${TIMESTAMP}.txt" << EOF
AMD PMC Performance Ratios for $test_name endpoint:
==================================================

L2 Cache Efficiency (PMCx064):
- L2 data hit rate = (ls_rd_blk_l_hit_s + ls_rd_blk_l_hit_x) / total_data_requests
- Target: >90% for object-heavy Rails workloads
- AMD advantage: 1MB L2 vs Intel 256KB-512KB

Instruction Cache Efficiency (PMCx064):
- I-cache hit rate = (ic_fill_hit_s + ic_fill_hit_x) / total_instruction_requests
- Target: >95% for stable Rails applications
- AMD advantage: Better branch prediction for Ruby dispatch

TLB Efficiency (PMCx045):
- TLB hit rate = 1 - (all_l2_miss / L1-dcache-loads)
- Target: >99% for well-tuned Rails
- AMD advantage: Larger TLB capacity

Memory Bandwidth Utilization (PMCx043/PMCx044):
- Memory pressure = local_mem / (local_l2 + local_mem)
- Target: <10% for CPU-bound Rails workloads
- AMD advantage: Higher DDR5 bandwidth on M8A instances
EOF
}

# Function to analyze Ruby GC performance
analyze_ruby_gc() {
    echo "Analyzing Ruby GC performance..."

    # Enable GC profiling
    export RUBY_GC_HEAP_INIT_SLOTS=1000000
    export RUBY_GC_HEAP_FREE_SLOTS=500000
    export RUBY_GC_HEAP_GROWTH_FACTOR=1.1

    # Restart Rails with GC stats
    pkill -f puma || true
    sleep 2

    cd /home/ubuntu/rails-benchmark
    GC_STAT=1 bundle exec puma -e production -p 3000 -b 0.0.0.0 &
    RAILS_PID=$!
    sleep 5

    # Test with GC monitoring
    echo "Testing with GC monitoring enabled..."
    wrk -t4 -c100 -d30s "$APP_URL/data" > "$RESULTS_DIR/gc_analysis_${TIMESTAMP}.txt"

    # Collect GC stats (if Rails configured to output them)
    ps -p $RAILS_PID -o pid,vsz,rss,pcpu,pmem > "$RESULTS_DIR/gc_memory_${TIMESTAMP}.txt"
}

# Main execution
echo "Starting performance analysis suite..."

# Check if application is running
if ! curl -s "$APP_URL/health" > /dev/null; then
    echo "Application not responding at $APP_URL"
    exit 1
fi

# Run analysis for each endpoint
run_perf_analysis "/hello" "hello_endpoint" 30
run_perf_analysis "/json" "json_endpoint" 30
run_perf_analysis "/data" "data_endpoint" 30

# Run Rails-specific PMC analysis for each endpoint
if [[ "$CPU_VENDOR" == "AuthenticAMD" ]]; then
    echo "Running Rails-optimized AMD PMC analysis..."
    analyze_rails_workloads "/hello" "hello_pmc" 30
    analyze_rails_workloads "/json" "json_pmc" 30
    analyze_rails_workloads "/data" "data_pmc" 30
fi

# Run perfspect if available
run_perfspect_analysis "/data" "data_perfspect"

# Run detailed profiling
run_detailed_profiling "/data" "data_detailed"

# Analyze Ruby GC
analyze_ruby_gc

# Generate summary report
cat > "$RESULTS_DIR/analysis_summary_${TIMESTAMP}.txt" << EOF
Performance Analysis Summary
============================
Date: $(date)
Instance: $INSTANCE_TYPE
CPU: $CPU_VENDOR - $CPU_MODEL
Cores: $(nproc)
Memory: $(free -h | grep Mem | awk '{print $2}')

Analysis Files Generated:
$(ls -la $RESULTS_DIR/*${TIMESTAMP}*)

Key Metrics to Compare:
1. Instructions per cycle (IPC): instructions/cycles
2. Cache miss rate: cache-misses/cache-references
3. Branch prediction: branch-misses/branches
4. L2 Cache efficiency (PMCx064): ls_rd_blk_l_hit_s/(ls_rd_blk_l_hit_s + ls_rd_blk_c)
5. TLB efficiency (PMCx045): 1 - (all_l2_miss/L1-dcache-loads)
6. Memory bandwidth (PMCx043): local_mem/(local_l2 + local_mem)

AMD PMC Register Analysis Points:
- PMCx064 L2 cache: Object locality and method dispatch efficiency
- PMCx045 TLB: Virtual memory performance for Ruby objects
- PMCx043/PMCx044 Data fills: Memory bandwidth utilization
- PMCx003 FP ops: Numeric processing efficiency
- Higher L2 hit rates = better object caching
- Lower TLB misses = efficient Ruby heap access
- Balanced memory/L2 fills = optimal cache hierarchy usage
EOF

echo ""
echo "=== Analysis Complete ==="
echo "Results saved to: $RESULTS_DIR"
echo "Summary: $RESULTS_DIR/analysis_summary_${TIMESTAMP}.txt"
echo ""
echo "Key files to examine:"
echo "1. Basic counters: *_basic_*.txt"
echo "2. Detailed counters: *_amd_detailed_*.txt (or intel/arm)"
echo "3. Profiling data: *_profile_*.txt"
echo "4. Summary: analysis_summary_*.txt"