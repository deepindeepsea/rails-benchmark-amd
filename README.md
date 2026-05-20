# Rails Benchmark Application

A simple Ruby on Rails "Hello World" application designed for performance benchmarking on AWS EC2 AMD instances (M7A/M8A).

## 🚀 Quick Start

### 1. Launch AWS EC2 Instance

```bash
# Recommended instance types for benchmarking:
# - m7a.large (2 vCPU, 8 GB RAM) - Good for basic testing
# - m7a.xlarge (4 vCPU, 16 GB RAM) - Better for load testing  
# - m7a.2xlarge (8 vCPU, 32 GB RAM) - Best for high-load scenarios
# - m8a.large (2 vCPU, 8 GB RAM) - Latest generation AMD
# - m8a.xlarge (4 vCPU, 16 GB RAM) - Latest generation medium
# - m8a.2xlarge (8 vCPU, 32 GB RAM) - Latest generation high-end

# Use Ubuntu 24.04 LTS AMI
```

### 2. One-Command Setup

```bash
# SSH into your EC2 instance
ssh -i your-key.pem ubuntu@your-instance-ip

# Clone and setup in one go
git clone https://github.com/your-username/rails-benchmark-amd.git
cd rails-benchmark-amd
chmod +x setup_ubuntu.sh
sudo ./setup_ubuntu.sh

# Restart shell to load Ruby environment
source ~/.bashrc
```

### 3. 🎯 Instance Optimization (NEW!)

```bash
# Auto-optimize for your specific instance type
chmod +x optimize_for_instance.sh
./optimize_for_instance.sh

# This automatically configures:
# - Optimal Puma worker count (utilizes all CPU cores)
# - Optimal thread count per worker
# - Optimal benchmark client threads
# - CPU core affinity (for 8+ core instances)
```

### 4. Deploy and Start

```bash
# Install dependencies
bundle install

# Start optimized server (uses all CPU cores)
source .env
bundle exec puma &
```

### 5. Test the Application

```bash
# Basic connectivity test
curl http://localhost:3000/health

# Test endpoints
curl http://localhost:3000/hello
curl http://localhost:3000/json
curl http://localhost:3000/data
curl http://localhost:3000/ping
```

### 6. Run Optimized Benchmarks

```bash
# Run the instance-optimized benchmark suite
./benchmark_optimized.sh

# Or run the original comprehensive suite
./benchmark_detailed.sh
```

## ⚡ Performance Optimization

### Auto-Optimization by Instance Type

The `optimize_for_instance.sh` script automatically configures optimal settings:

| Instance Type | Workers | Threads/Worker | Client Threads | Total Handlers | Expected /hello RPS |
|---------------|---------|----------------|----------------|----------------|-------------------|
| m7a.large     | 2       | 8              | 2              | 16             | 12k-18k          |
| m7a.xlarge    | 3       | 12             | 4              | 36             | 25k-35k          |
| m7a.2xlarge   | 7       | 16             | 8              | 112            | 45k-65k          |
| m8a.large     | 2       | 8              | 2              | 16             | 15k-20k          |
| m8a.xlarge    | 3       | 12             | 4              | 36             | 30k-40k          |
| m8a.2xlarge   | 7       | 16             | 8              | 112            | 50k-70k          |

### CPU Core Utilization

**M8a.2xlarge (8 vCPU) Example:**
```
Core Allocation:
├── Cores 0-6: Puma workers (7 workers, server-side)
├── Core 7: wrk benchmark client + system overhead
├── Total Server Cores: 7 (87.5% dedicated to serving)
├── Total Client Cores: 1 (shared with system)
└── CPU Utilization: ~95% during benchmarks
```

**Key Features:**
- **Full core utilization**: Uses (cores-1) for server, all cores for client
- **CPU affinity**: Pins workers to specific cores (8+ core instances)
- **Automatic scaling**: Detects instance type and optimizes accordingly
- **Real-time monitoring**: Shows per-core utilization during tests

## Available Endpoints

| Endpoint | Description | Use Case |
|----------|-------------|----------|
| `/` | Root endpoint | Basic HTML response |
| `/hello` | Simple text response | Minimal overhead testing |
| `/ping` | Ultra-simple "pong" response | Network latency testing |
| `/json` | JSON response with metadata | API performance testing |
| `/data` | JSON with data processing | CPU-bound workload testing |
| `/health` | System health check | Monitoring and diagnostics |

## Configuration Options

### Puma Configuration (High Performance)

Create `config/puma.rb`:

```ruby
# config/puma.rb
workers ENV.fetch("WEB_CONCURRENCY") { 4 }
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
threads threads_count, threads_count

preload_app!

rackup      DefaultRackup
port        ENV.fetch("PORT") { 3000 }
environment ENV.fetch("RAILS_ENV") { "production" }

on_worker_boot do
  # Worker specific setup
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
end

# Allow puma to be restarted by `rails restart` command.
plugin :tmp_restart
```

### Environment Variables

```bash
# Performance tuning
export WEB_CONCURRENCY=4           # Number of worker processes
export RAILS_MAX_THREADS=8         # Threads per worker
export RAILS_MIN_THREADS=8         # Minimum threads
export RAILS_ENV=production        # Production environment
export RACK_ENV=production         # Rack environment
export RAILS_LOG_LEVEL=error       # Minimal logging for performance
export RAILS_SERVE_STATIC_FILES=true  # Serve static files

# Security
export SECRET_KEY_BASE=$(rails secret)

# Database (if using)
export DATABASE_URL=sqlite3:benchmark.db
```

## Benchmark Tools Usage

### Apache Bench (ab)
```bash
# Simple test: 10k requests, 50 concurrent
ab -n 10000 -c 50 http://localhost:3000/hello

# With graphing data
ab -n 10000 -c 50 -g results.dat http://localhost:3000/hello
```

### wrk (Recommended)
```bash
# Basic load test: 12 threads, 400 connections, 30 seconds
wrk -t12 -c400 -d30s http://localhost:3000/hello

# With latency statistics
wrk -t12 -c400 -d30s --latency http://localhost:3000/hello

# JSON endpoint test
wrk -t8 -c200 -d15s http://localhost:3000/json
```

### Siege
```bash
# Continuous bombardment
siege -c50 -t30s http://localhost:3000/hello

# Specific number of requests
siege -c20 -r100 http://localhost:3000/hello
```

## Performance Optimization Tips

### 1. System Level
```bash
# Increase file descriptor limits
echo "* soft nofile 1048576" | sudo tee -a /etc/security/limits.conf
echo "* hard nofile 1048576" | sudo tee -a /etc/security/limits.conf

# Network optimizations
sudo sysctl -w net.core.somaxconn=65535
sudo sysctl -w net.core.netdev_max_backlog=5000
```

### 2. Rails Level
```bash
# Use production environment
export RAILS_ENV=production

# Disable logging for maximum performance
export RAILS_LOG_LEVEL=error

# Use memory store for caching
# (already configured in config/environments/production.rb)
```

### 3. Puma Level
```bash
# Optimize worker count (typically CPU cores)
export WEB_CONCURRENCY=$(nproc)

# Optimize thread count (experiment with values)
export RAILS_MAX_THREADS=16
export RAILS_MIN_THREADS=16
```

## Monitoring and Debugging

### System Monitoring
```bash
# CPU and memory usage
htop

# Network connections
ss -tuln

# Application process
ps aux | grep puma

# System performance
iostat -x 1
vmstat 1
```

### Application Monitoring
```bash
# Rails logs
tail -f log/production.log

# Puma process status
ps aux | grep puma

# Check listening ports
netstat -tlnp | grep :3000
```

## AWS-Specific Considerations

### Security Groups
- Port 22 (SSH): Your IP only
- Port 80 (HTTP): 0.0.0.0/0 (if using Nginx)
- Port 3000 (Rails): 0.0.0.0/0 (for testing) or specific IPs
- Port 443 (HTTPS): 0.0.0.0/0 (if using SSL)

### Instance Types

| Instance Type | vCPUs | RAM | Network Performance | Best For |
|--------------|-------|-----|-------------------|----------|
| m7a.large | 2 | 8 GB | Up to 12.5 Gbps | Basic testing |
| m7a.xlarge | 4 | 16 GB | Up to 12.5 Gbps | Load testing |
| m7a.2xlarge | 8 | 32 GB | Up to 12.5 Gbps | High-load testing |
| m8a.large | 2 | 8 GB | Up to 12.5 Gbps | Latest gen testing |

### CloudWatch Metrics
Enable detailed monitoring for:
- CPU utilization
- Network I/O
- Memory utilization (with CloudWatch agent)

## Troubleshooting

### Common Issues

1. **Ruby/Rails not found after setup**
   ```bash
   source ~/.bashrc
   export PATH="$HOME/.rbenv/bin:$PATH"
   eval "$(rbenv init -)"
   ```

2. **Port already in use**
   ```bash
   sudo lsof -i :3000
   sudo kill -9 <PID>
   ```

3. **Permission denied**
   ```bash
   sudo chown -R ubuntu:ubuntu /home/ubuntu/rails-benchmark
   chmod +x benchmark.sh
   ```

4. **Out of memory**
   ```bash
   # Check swap
   free -h
   # Reduce worker processes
   export WEB_CONCURRENCY=2
   ```

## Expected Performance

On a typical m7a.large instance:
- **Simple endpoints (/hello, /ping)**: 8,000-15,000 RPS
- **JSON endpoints (/json)**: 6,000-10,000 RPS
- **Data processing (/data)**: 2,000-5,000 RPS

Performance varies based on:
- Instance type and size
- Network conditions
- Concurrent users
- Application configuration
- System optimization

## License

MIT License - Feel free to use and modify for your benchmarking needs.