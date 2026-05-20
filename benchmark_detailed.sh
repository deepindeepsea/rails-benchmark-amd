#!/bin/bash

# Detailed Rails Benchmark Script with RPS Measurement
# Tests various endpoints and provides comprehensive performance metrics

APP_URL="${1:-http://localhost:3000}"
RESULTS_DIR="/home/ubuntu/benchmark-results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="$RESULTS_DIR/benchmark_report_$TIMESTAMP.txt"

# Create results directory
mkdir -p $RESULTS_DIR

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Rails Benchmark Test Suite ===${NC}"
echo -e "Testing Rails application at: ${GREEN}$APP_URL${NC}"
echo -e "Results directory: ${GREEN}$RESULTS_DIR${NC}"
echo -e "Report file: ${GREEN}$REPORT_FILE${NC}"
echo ""

# Initialize report file
cat > "$REPORT_FILE" << EOF
Rails Benchmark Report
======================
Date: $(date)
Target URL: $APP_URL
Instance: $(curl -s http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null || echo "Unknown")
AZ: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone 2>/dev/null || echo "Unknown")

System Information:
------------------
CPU: $(lscpu | grep 'Model name' | cut -d: -f2 | xargs)
CPU Cores: $(nproc)
Memory: $(free -h | grep Mem | awk '{print $2}')
Uptime: $(uptime)

EOF

# Function to check if application is responding
check_app_health() {
    echo -e "${YELLOW}Checking application health...${NC}"

    for i in {1..30}; do
        if curl -s "$APP_URL/health" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Application is responding!${NC}"

            # Get health info
            HEALTH_INFO=$(curl -s "$APP_URL/health")
            echo "Health Check Response:" >> "$REPORT_FILE"
            echo "$HEALTH_INFO" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"

            return 0
        fi
        echo -e "  Waiting for application... (${i}/30)"
        sleep 2
    done

    echo -e "${RED}✗ Application is not responding!${NC}"
    echo "ERROR: Application not responding after 60 seconds" >> "$REPORT_FILE"
    exit 1
}

# Function to extract RPS from wrk output
extract_rps_wrk() {
    local file="$1"
    local rps=$(grep "Requests/sec:" "$file" | awk '{print $2}')
    echo "$rps"
}

# Function to extract RPS from ab output
extract_rps_ab() {
    local file="$1"
    local rps=$(grep "Requests per second:" "$file" | awk '{print $4}')
    echo "$rps"
}

# Function to run benchmark test
run_benchmark() {
    local name="$1"
    local endpoint="$2"
    local tool="$3"
    local params="$4"

    echo -e "${BLUE}Running $name test...${NC}"
    echo "Running $name test..." >> "$REPORT_FILE"

    local test_file="$RESULTS_DIR/${name// /_}_${tool}_$TIMESTAMP.txt"
    local url="$APP_URL$endpoint"

    case $tool in
        "wrk")
            timeout 60 wrk $params "$url" > "$test_file" 2>&1
            local rps=$(extract_rps_wrk "$test_file")
            ;;
        "ab")
            timeout 60 ab $params "$url" > "$test_file" 2>&1
            local rps=$(extract_rps_ab "$test_file")
            ;;
        "siege")
            timeout 60 siege $params "$url" > "$test_file" 2>&1
            local rps=$(grep "Transaction rate:" "$test_file" | awk '{print $3}')
            ;;
    esac

    echo "  Tool: $tool, RPS: ${rps:-'N/A'}"
    echo "  Results saved to: $test_file"

    # Add to report
    echo "Test: $name" >> "$REPORT_FILE"
    echo "Tool: $tool" >> "$REPORT_FILE"
    echo "Endpoint: $endpoint" >> "$REPORT_FILE"
    echo "RPS: ${rps:-'N/A'}" >> "$REPORT_FILE"
    echo "Full results: $test_file" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    # Display key metrics
    if [[ "$tool" == "wrk" ]]; then
        echo "  $(grep "Latency" "$test_file" || echo "  Latency info not available")"
        echo "  $(grep "Req/Sec" "$test_file" || echo "  Req/Sec info not available")"
    elif [[ "$tool" == "ab" ]]; then
        echo "  $(grep "Time per request" "$test_file" | head -1 || echo "  Time per request info not available")"
        echo "  $(grep "Transfer rate" "$test_file" || echo "  Transfer rate info not available")"
    fi

    echo ""
}

# Function to run system monitoring during tests
start_monitoring() {
    echo -e "${YELLOW}Starting system monitoring...${NC}"

    # Start background monitoring
    (
        while true; do
            echo "$(date): CPU: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}'), Memory: $(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')" >> "$RESULTS_DIR/system_monitor_$TIMESTAMP.log"
            sleep 5
        done
    ) &
    MONITOR_PID=$!
    echo "System monitoring started (PID: $MONITOR_PID)"
}

# Function to stop system monitoring
stop_monitoring() {
    if [[ -n "$MONITOR_PID" ]]; then
        kill $MONITOR_PID 2>/dev/null
        echo -e "${YELLOW}System monitoring stopped${NC}"
    fi
}

# Trap to cleanup monitoring on exit
trap stop_monitoring EXIT

# Main execution
echo -e "${BLUE}Starting comprehensive benchmark suite...${NC}"
echo ""

# Check application health
check_app_health

# Start system monitoring
start_monitoring

# Test 1: Simple Hello endpoint - Light load
run_benchmark "Hello Light Load" "/hello" "wrk" "-t4 -c50 -d15s --latency"
run_benchmark "Hello Light Load" "/hello" "ab" "-n 5000 -c 25"

# Test 2: Simple Hello endpoint - Medium load
run_benchmark "Hello Medium Load" "/hello" "wrk" "-t8 -c200 -d30s --latency"
run_benchmark "Hello Medium Load" "/hello" "ab" "-n 10000 -c 100"

# Test 3: Simple Hello endpoint - Heavy load
run_benchmark "Hello Heavy Load" "/hello" "wrk" "-t12 -c400 -d30s --latency"
run_benchmark "Hello Heavy Load" "/hello" "ab" "-n 20000 -c 200"

# Test 4: Ping endpoint (minimal processing)
run_benchmark "Ping Test" "/ping" "wrk" "-t8 -c200 -d15s"
run_benchmark "Ping Test" "/ping" "ab" "-n 10000 -c 100"

# Test 5: JSON endpoint
run_benchmark "JSON Response" "/json" "wrk" "-t8 -c200 -d20s"
run_benchmark "JSON Response" "/json" "ab" "-n 8000 -c 80"

# Test 6: Data processing endpoint
run_benchmark "Data Processing" "/data" "wrk" "-t4 -c100 -d20s"
run_benchmark "Data Processing" "/data" "ab" "-n 5000 -c 50"

# Test 7: Health endpoint
run_benchmark "Health Check" "/health" "wrk" "-t4 -c50 -d10s"

# Test 8: Siege endurance test
echo -e "${BLUE}Running endurance test with Siege...${NC}"
run_benchmark "Endurance Test" "/hello" "siege" "-c50 -t60s"

# Generate summary report
echo -e "${BLUE}Generating summary report...${NC}"

cat >> "$REPORT_FILE" << 'EOF'

Summary Statistics:
==================
EOF

# Extract all RPS values for summary
echo "RPS Summary:" >> "$REPORT_FILE"
grep "RPS:" "$REPORT_FILE" | grep -v "Summary" >> "$REPORT_FILE"

# System resource usage during tests
echo "" >> "$REPORT_FILE"
echo "System Resource Usage During Tests:" >> "$REPORT_FILE"
if [[ -f "$RESULTS_DIR/system_monitor_$TIMESTAMP.log" ]]; then
    echo "Peak CPU usage: $(cat "$RESULTS_DIR/system_monitor_$TIMESTAMP.log" | grep -o 'CPU: [0-9.]*%' | sort -nr | head -1)" >> "$REPORT_FILE"
    echo "Peak Memory usage: $(cat "$RESULTS_DIR/system_monitor_$TIMESTAMP.log" | grep -o 'Memory: [0-9.]*%' | sort -nr | head -1)" >> "$REPORT_FILE"
fi

# Final system state
echo "" >> "$REPORT_FILE"
echo "Final System State:" >> "$REPORT_FILE"
echo "CPU Load: $(uptime | awk -F'load average:' '{print $2}')" >> "$REPORT_FILE"
echo "Memory Usage: $(free | grep Mem | awk '{printf "%.1f%% (%s/%s)", $3/$2 * 100.0, $3, $2}')" >> "$REPORT_FILE"
echo "Network Connections: $(ss -tun | wc -l)" >> "$REPORT_FILE"

# Display final summary
echo -e "${GREEN}=== Benchmark Complete! ===${NC}"
echo -e "Full report saved to: ${GREEN}$REPORT_FILE${NC}"
echo -e "Individual test results in: ${GREEN}$RESULTS_DIR${NC}"
echo ""
echo -e "${BLUE}Quick Summary:${NC}"

# Display top RPS results
echo "Top RPS Results:"
grep "RPS:" "$REPORT_FILE" | grep -v "Summary" | sort -nr -k2 | head -5 | while read line; do
    echo "  $line"
done

echo ""
echo -e "${YELLOW}To view full results:${NC}"
echo "  cat '$REPORT_FILE'"
echo "  ls -la '$RESULTS_DIR'"

# Cleanup
stop_monitoring