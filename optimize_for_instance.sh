#!/bin/bash

# Auto-optimize Rails and benchmark configuration for current instance
# Detects AWS instance type and sets optimal settings

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Instance Optimization Script ===${NC}"

# Detect instance information
INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null || echo "unknown")
CPU_CORES=$(nproc)
TOTAL_MEMORY=$(free -g | grep Mem | awk '{print $2}')

echo -e "Instance Type: ${GREEN}$INSTANCE_TYPE${NC}"
echo -e "CPU Cores: ${GREEN}$CPU_CORES${NC}"
echo -e "Total Memory: ${GREEN}${TOTAL_MEMORY}GB${NC}"

# Calculate optimal configuration
if [[ $CPU_CORES -ge 8 ]]; then
    # 8+ core instances (m7a.2xlarge, m8a.2xlarge, etc.)
    WEB_CONCURRENCY=$((CPU_CORES - 1))  # Leave 1 core for client/system
    RAILS_MAX_THREADS=16
    WRK_THREADS=$((CPU_CORES))          # Use all cores for client
    HEAVY_CONNECTIONS=800
    MEDIUM_CONNECTIONS=400
    echo -e "${GREEN}Optimizing for high-core instance${NC}"
elif [[ $CPU_CORES -ge 4 ]]; then
    # 4-7 core instances (m7a.xlarge, m8a.xlarge)
    WEB_CONCURRENCY=$((CPU_CORES - 1))
    RAILS_MAX_THREADS=12
    WRK_THREADS=$CPU_CORES
    HEAVY_CONNECTIONS=400
    MEDIUM_CONNECTIONS=200
    echo -e "${GREEN}Optimizing for medium-core instance${NC}"
else
    # 2-3 core instances (m7a.large, m8a.large)
    WEB_CONCURRENCY=$CPU_CORES
    RAILS_MAX_THREADS=8
    WRK_THREADS=$CPU_CORES
    HEAVY_CONNECTIONS=200
    MEDIUM_CONNECTIONS=100
    echo -e "${GREEN}Optimizing for small-core instance${NC}"
fi

# Create optimized environment file
cat > /home/ubuntu/rails-benchmark/.env << EOF
# Auto-generated optimization for $INSTANCE_TYPE ($CPU_CORES cores)
export WEB_CONCURRENCY=$WEB_CONCURRENCY
export RAILS_MAX_THREADS=$RAILS_MAX_THREADS
export RAILS_MIN_THREADS=$RAILS_MAX_THREADS
export RAILS_ENV=production
export RACK_ENV=production
export RAILS_LOG_LEVEL=error
export RAILS_SERVE_STATIC_FILES=true
export RAILS_LOG_TO_STDOUT=true
export SECRET_KEY_BASE=\$(rails secret)

# Benchmark tool settings
export WRK_THREADS=$WRK_THREADS
export HEAVY_CONNECTIONS=$HEAVY_CONNECTIONS
export MEDIUM_CONNECTIONS=$MEDIUM_CONNECTIONS

# Performance tuning
export MALLOC_ARENA_MAX=2
export RUBY_GC_HEAP_INIT_SLOTS=1000000
export RUBY_GC_HEAP_FREE_SLOTS=500000
export RUBY_GC_HEAP_GROWTH_FACTOR=1.1
export RUBY_GC_HEAP_GROWTH_MAX_SLOTS=0
EOF

# Create optimized Puma configuration
cat > /home/ubuntu/rails-benchmark/config/puma.rb << EOF
# Auto-optimized Puma config for $INSTANCE_TYPE ($CPU_CORES cores)

workers ENV.fetch("WEB_CONCURRENCY") { $WEB_CONCURRENCY }
threads_count = ENV.fetch("RAILS_MAX_THREADS") { $RAILS_MAX_THREADS }
threads threads_count, threads_count

preload_app!
rackup DefaultRackup
port ENV.fetch("PORT") { 3000 }
environment ENV.fetch("RAILS_ENV") { "production" }
bind "tcp://0.0.0.0:#{ENV.fetch("PORT") { 3000 }}"

# Performance optimizations for $CPU_CORES core system
worker_timeout 60
worker_boot_timeout 60

# Memory optimization
nakayoshi_fork if ENV["RAILS_ENV"] == "production"

# CPU affinity for workers (if supported)
if CPU_CORES >= 8
  # Pin workers to specific CPU cores for better cache locality
  before_fork do
    require 'etc'
  end

  on_worker_boot do |index|
    # Pin each worker to specific cores
    if File.exist?('/usr/bin/taskset')
      core = index % $CPU_CORES
      system("taskset -pc #{core} #{Process.pid}")
    end

    ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
  end
end

# Logging
stdout_redirect '/home/ubuntu/rails-benchmark/log/puma.stdout.log',
                '/home/ubuntu/rails-benchmark/log/puma.stderr.log', true

pidfile '/home/ubuntu/rails-benchmark/tmp/pids/puma.pid'
state_path '/home/ubuntu/rails-benchmark/tmp/pids/puma.state'

plugin :tmp_restart
EOF

# Create instance-optimized benchmark script
cat > /home/ubuntu/rails-benchmark/benchmark_optimized.sh << 'EOF'
#!/bin/bash

# Instance-optimized benchmark script
# Uses environment variables set by optimize_for_instance.sh

APP_URL="${1:-http://localhost:3000}"
RESULTS_DIR="/home/ubuntu/benchmark-results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Load optimized settings
source /home/ubuntu/rails-benchmark/.env

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Optimized Benchmark Suite ===${NC}"
echo -e "Instance optimization: ${GREEN}$WEB_CONCURRENCY workers, $RAILS_MAX_THREADS threads${NC}"
echo -e "Client threads: ${GREEN}$WRK_THREADS${NC}"
echo -e "CPU cores detected: ${GREEN}$(nproc)${NC}"

mkdir -p $RESULTS_DIR

# Function to check app health
check_app_health() {
    echo -e "${YELLOW}Checking application health...${NC}"
    for i in {1..30}; do
        if curl -s "$APP_URL/health" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Application is responding!${NC}"
            return 0
        fi
        echo "  Waiting for application... ($i/30)"
        sleep 2
    done
    echo -e "${RED}✗ Application not responding!${NC}"
    exit 1
}

# Function to show CPU usage during test
monitor_cpu() {
    echo -e "${YELLOW}CPU core utilization during test:${NC}"
    # Show per-core CPU usage
    mpstat -P ALL 1 1 | grep -A $(nproc) "Average.*CPU"
}

# Run optimized benchmark tests
run_optimized_test() {
    local name="$1"
    local endpoint="$2"
    local duration="$3"
    local connections="$4"

    echo -e "${BLUE}Running $name...${NC}"
    echo "  Connections: $connections, Threads: $WRK_THREADS, Duration: ${duration}s"

    # Pre-test CPU measurement
    echo "  CPU usage before test:"
    mpstat 1 1 | grep "Average" | awk '{print "    Average CPU: " (100-$NF) "%"}'

    # Run the test
    wrk -t$WRK_THREADS -c$connections -d${duration}s --latency "$APP_URL$endpoint" \
        > "$RESULTS_DIR/${name// /_}_optimized_$TIMESTAMP.txt" 2>&1

    # Extract and display RPS
    local rps=$(grep "Requests/sec:" "$RESULTS_DIR/${name// /_}_optimized_$TIMESTAMP.txt" | awk '{print $2}')
    echo -e "  Result: ${GREEN}${rps} RPS${NC}"

    # Post-test CPU measurement
    echo "  CPU usage during test peak:"
    mpstat 1 1 | grep "Average" | awk '{print "    Average CPU: " (100-$NF) "%"}'

    echo ""
}

# Check application
check_app_health

# Show initial system state
echo -e "${BLUE}Initial system state:${NC}"
echo "  Load average: $(uptime | awk -F'load average:' '{print $2}')"
echo "  Memory usage: $(free | grep Mem | awk '{printf "%.1f%% (%s/%s)", $3/$2 * 100.0, $3, $2}')"
echo ""

# Run optimized test suite
run_optimized_test "Light Load Test" "/hello" 15 $((MEDIUM_CONNECTIONS / 2))
run_optimized_test "Medium Load Test" "/hello" 30 $MEDIUM_CONNECTIONS
run_optimized_test "Heavy Load Test" "/hello" 30 $HEAVY_CONNECTIONS
run_optimized_test "JSON Test" "/json" 20 $MEDIUM_CONNECTIONS
run_optimized_test "Data Processing Test" "/data" 20 $((MEDIUM_CONNECTIONS / 2))

# Final system state
echo -e "${BLUE}Final system state:${NC}"
echo "  Load average: $(uptime | awk -F'load average:' '{print $2}')"
echo "  Memory usage: $(free | grep Mem | awk '{printf "%.1f%% (%s/%s)", $3/$2 * 100.0, $3, $2}')"

# Show per-core utilization summary
echo -e "${BLUE}Per-core utilization summary:${NC}"
monitor_cpu

echo -e "${GREEN}Optimized benchmark complete!${NC}"
echo "Results saved to: $RESULTS_DIR"

# Show top RPS results
echo -e "${BLUE}Performance Summary:${NC}"
grep "Requests/sec:" $RESULTS_DIR/*optimized_$TIMESTAMP.txt | \
    awk -F: '{print $1 ": " $3}' | \
    sort -nr -k2 | \
    head -5
EOF

chmod +x /home/ubuntu/rails-benchmark/benchmark_optimized.sh

echo ""
echo -e "${GREEN}=== Optimization Complete! ===${NC}"
echo ""
echo "Configuration applied:"
echo -e "  Puma Workers: ${GREEN}$WEB_CONCURRENCY${NC} (using $((WEB_CONCURRENCY)) cores)"
echo -e "  Threads/Worker: ${GREEN}$RAILS_MAX_THREADS${NC}"
echo -e "  Client Threads: ${GREEN}$WRK_THREADS${NC} (using $WRK_THREADS cores)"
echo -e "  Total Request Handlers: ${GREEN}$((WEB_CONCURRENCY * RAILS_MAX_THREADS))${NC}"
echo ""
echo "Core allocation:"
echo -e "  Server cores: ${GREEN}$WEB_CONCURRENCY${NC} (Puma workers)"
echo -e "  Client cores: ${GREEN}$WRK_THREADS${NC} (wrk threads)"
echo -e "  System cores: ${GREEN}1${NC} (OS + monitoring)"
echo -e "  Total: ${GREEN}$CPU_CORES${NC} cores"
echo ""
echo "To apply settings and run optimized benchmark:"
echo -e "${YELLOW}source /home/ubuntu/rails-benchmark/.env${NC}"
echo -e "${YELLOW}cd /home/ubuntu/rails-benchmark && bundle exec puma &${NC}"
echo -e "${YELLOW}./benchmark_optimized.sh${NC}"