#!/bin/bash

# Simple Pipeline Utilization Test using perf direct commands

echo "=== Testing perf pipeline stats directly ==="
echo "CPU: $(lscpu | grep 'Model name' | cut -d: -f2 | xargs)"
echo ""

echo "1. Testing perf stat with topdown analysis..."
perf stat --topdown dd if=/dev/zero of=/tmp/test bs=1M count=100 2>&1
rm -f /tmp/test
echo ""

echo "2. Testing detailed pipeline breakdown..."
perf stat -d dd if=/dev/zero of=/tmp/test bs=1M count=100 2>&1
rm -f /tmp/test
echo ""

echo "3. Testing very detailed analysis..."
perf stat -ddd dd if=/dev/zero of=/tmp/test bs=1M count=100 2>&1
rm -f /tmp/test
echo ""

echo "4. Testing specific AMD cache events..."
perf stat -e cache-references,cache-misses,branches,branch-misses,L1-dcache-loads,L1-dcache-load-misses \
dd if=/dev/zero of=/tmp/test bs=1M count=100 2>&1
rm -f /tmp/test
echo ""

echo "5. Testing available AMD-specific events..."
echo "Available L2 events:"
perf list | grep -i l2 | head -10

echo "Available TLB events:"
perf list | grep -i tlb | head -10

echo "Available branch events:"
perf list | grep -i branch | head -10

echo ""
echo "=== Test Complete ==="
echo "The --topdown flag should show pipeline utilization breakdown automatically."
echo "The -d/-dd/-ddd flags show progressively more detailed metrics."