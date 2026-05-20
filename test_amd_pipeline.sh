#!/bin/bash

# AMD-Specific Pipeline Analysis Test
# Using real AMD performance counters from PerfSpect

echo "=== AMD Pipeline Utilization Test ==="
echo "CPU: $(lscpu | grep 'Model name' | cut -d: -f2 | xargs)"
echo ""

echo "1. Testing basic AMD core events..."
perf stat -e cpu-cycles,instructions,ex_ret_brn,ex_ret_brn_misp \
dd if=/dev/zero of=/tmp/test bs=1M count=100 2>&1
rm -f /tmp/test
echo ""

echo "2. Testing AMD Frontend events..."
# These are from PerfSpect's AMD pipeline utilization formulas
perf stat -e de_no_dispatch_per_slot.no_ops_from_frontend,de_no_dispatch_per_cycle.no_ops_from_frontend,ls_not_halted_cyc \
dd if=/dev/zero of=/tmp/test bs=1M count=100 2>&1 || echo "Frontend events not available on this kernel/system"
rm -f /tmp/test
echo ""

echo "3. Testing AMD Backend events..."
perf stat -e de_no_dispatch_per_slot.backend_stalls,ex_no_retire.load_not_complete,ex_no_retire.not_complete \
dd if=/dev/zero of=/tmp/test bs=1M count=100 2>&1 || echo "Backend events not available on this kernel/system"
rm -f /tmp/test
echo ""

echo "4. Testing AMD Speculation events..."
perf stat -e de_src_op_disp.all,ex_ret_ops,resyncs_or_nc_redirects \
dd if=/dev/zero of=/tmp/test bs=1M count=100 2>&1 || echo "Speculation events not available on this kernel/system"
rm -f /tmp/test
echo ""

echo "5. Testing AMD Retirement events..."
perf stat -e ex_ret_ops,ex_ret_ucode_ops \
dd if=/dev/zero of=/tmp/test bs=1M count=100 2>&1 || echo "Retirement events not available on this kernel/system"
rm -f /tmp/test
echo ""

echo "6. Testing available events that actually work..."
echo "Let's see what AMD events are actually supported:"
echo ""

echo "Testing symbolic AMD events:"
perf stat -e instructions,cpu-cycles,branches,branch-misses \
dd if=/dev/zero of=/tmp/test bs=1M count=50 2>&1
rm -f /tmp/test
echo ""

echo "Testing L1 cache events:"
perf stat -e L1-dcache-loads,L1-dcache-load-misses,L1-icache-load-misses \
dd if=/dev/zero of=/tmp/test bs=1M count=50 2>&1
rm -f /tmp/test
echo ""

echo "Testing what's available in perf list:"
echo "AMD-specific events available:"
perf list | grep -E "(amd|ls_|ex_|de_|l2_|l3_)" | head -20

echo ""
echo "=== Key Insight ==="
echo "Intel TopDown ≠ AMD Pipeline Analysis"
echo "We need AMD-specific events and PerfSpect formulas for meaningful pipeline analysis"
echo ""
echo "If the symbolic events work (instructions, cpu-cycles, branches), we can build"
echo "AMD pipeline metrics using PerfSpect's proven formulas rather than Intel's TopDown."