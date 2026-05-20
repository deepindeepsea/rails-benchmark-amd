# Rails Benchmark Application Architecture

## Overview

This Rails benchmark application is designed to measure the performance of Ruby on Rails applications running on AWS EC2 AMD instances (M7A/M8A). The architecture is optimized for simplicity, performance, and accurate RPS (Requests Per Second) measurement.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        AWS EC2 Instance                        │
│                     (AMD M7A/M8A)                              │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐    ┌─────────────────┐                   │
│  │  Load Testing   │    │   Monitoring    │                   │
│  │     Tools       │    │     Tools       │                   │
│  │  ┌───────────┐  │    │  ┌───────────┐  │                   │
│  │  │    wrk    │  │    │  │   htop    │  │                   │
│  │  │    ab     │  │    │  │  iostat   │  │                   │
│  │  │   siege   │  │    │  │  vmstat   │  │                   │
│  │  └───────────┘  │    │  └───────────┘  │                   │
│  └─────────────────┘    └─────────────────┘                   │
│           │                       │                           │
│           │                       │                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    Network Layer                       │   │
│  │  ┌─────────────┐  Optional  ┌─────────────────────────┐ │   │
│  │  │   Nginx     │  ◄─────────┤        Direct           │ │   │
│  │  │ (Reverse    │             │      Connection         │ │   │
│  │  │   Proxy)    │             │    (Port 3000)          │ │   │
│  │  └─────────────┘             └─────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────┘   │
│           │                                                   │
│           ▼                                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │               Ruby on Rails Application                │   │
│  │                                                       │   │
│  │  ┌─────────────────┐  ┌─────────────────────────────┐  │   │
│  │  │      Puma       │  │          Rails App          │  │   │
│  │  │   Web Server    │  │                             │  │   │
│  │  │                 │  │  ┌─────────────────────────┐ │  │   │
│  │  │ ┌─────────────┐ │  │  │     HomeController      │ │  │   │
│  │  │ │ Worker 1    │ │  │  │                         │ │  │   │
│  │  │ │ (8 threads) │ │  │  │  /hello  - Simple text  │ │  │   │
│  │  │ └─────────────┘ │  │  │  /ping   - Ultra simple │ │  │   │
│  │  │ ┌─────────────┐ │  │  │  /json   - JSON response │ │  │   │
│  │  │ │ Worker 2    │ │  │  │  /data   - Data proc.   │ │  │   │
│  │  │ │ (8 threads) │ │  │  │  /health - Health check │ │  │   │
│  │  │ └─────────────┘ │  │  └─────────────────────────┘ │  │   │
│  │  │ ┌─────────────┐ │  └─────────────────────────────────┘  │   │
│  │  │ │ Worker 3    │ │                                       │   │
│  │  │ │ (8 threads) │ │                                       │   │
│  │  │ └─────────────┘ │                                       │   │
│  │  │ ┌─────────────┐ │                                       │   │
│  │  │ │ Worker 4    │ │                                       │   │
│  │  │ │ (8 threads) │ │                                       │   │
│  │  │ └─────────────┘ │                                       │   │
│  │  └─────────────────┘                                       │   │
│  └─────────────────────────────────────────────────────────────┘   │
│           │                                                       │
│           ▼                                                       │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                  Operating System                          │   │
│  │              Ubuntu 24.04 LTS                              │   │
│  │                                                           │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐   │   │
│  │  │   Ruby      │  │   System    │  │    Network      │   │   │
│  │  │    3.2.0    │  │   Tuning    │  │   Optimization  │   │   │
│  │  └─────────────┘  │ (sysctl)    │  │   (TCP tuning)  │   │   │
│  │                   └─────────────┘  └─────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Component Details

### 1. Web Server Layer (Puma)

**Configuration:**
- **Workers**: 4 processes (configurable via `WEB_CONCURRENCY`)
- **Threads per worker**: 8 threads (configurable via `RAILS_MAX_THREADS`)
- **Total capacity**: 32 concurrent request handlers
- **Binding**: `0.0.0.0:3000` for external access

**Why Puma:**
- Native thread support for true parallelism
- Cluster mode for multi-core utilization
- Low memory footprint compared to alternatives
- Excellent performance on AMD processors

### 2. Rails Application Layer

**Framework:** Ruby on Rails 7.1
- **Ruby Version**: 3.2.0 (optimized for performance)
- **Environment**: Production mode for benchmarking
- **Caching**: Memory store for fast access
- **Logging**: Minimized for performance (ERROR level)

**Endpoints Architecture:**

```ruby
# Complexity levels for different performance testing scenarios

GET /ping         # Ultra-minimal: "pong" string
                  # Tests: Raw network + minimal Ruby processing

GET /hello        # Simple: "Hello World!" plain text
                  # Tests: Basic Rails routing + controller action

GET /json         # Structured: JSON with metadata
                  # Tests: JSON serialization + system info gathering

GET /data         # Processing: JSON with calculations
                  # Tests: CPU-bound work + data manipulation

GET /health       # Comprehensive: System health metrics
                  # Tests: File I/O + system calls + JSON serialization
```

### 3. Operating System Layer

**Base OS:** Ubuntu 24.04 LTS
- **Kernel**: Linux 6.8+ with AMD-optimized defaults
- **Package Manager**: APT with universe repositories enabled
- **Dependencies**: Build tools, Ruby development headers, system monitoring tools

**System Optimizations:**
```bash
# Network stack tuning for high RPS
net.core.somaxconn = 65535              # Socket listen backlog
net.core.netdev_max_backlog = 5000      # Network device backlog
net.ipv4.tcp_max_syn_backlog = 65535    # TCP SYN backlog
net.ipv4.tcp_fin_timeout = 10           # Fast FIN timeout
net.ipv4.tcp_tw_reuse = 1               # Reuse TIME_WAIT sockets

# File descriptor limits
fs.file-max = 2097152                   # System-wide file descriptors
* soft nofile 1048576                   # Per-process file descriptors
* hard nofile 1048576
```

### 4. AWS Infrastructure Layer

**Instance Types:**
- **m7a.large**: 2 vCPU, 8 GB RAM - Basic testing baseline
- **m7a.xlarge**: 4 vCPU, 16 GB RAM - Recommended for load testing
- **m7a.2xlarge**: 8 vCPU, 32 GB RAM - High-load scenarios
- **m8a.large**: 2 vCPU, 8 GB RAM - Latest generation testing

**AMD Processor Benefits:**
- **High IPC (Instructions Per Cycle)**: Better single-thread performance
- **Multi-threading**: Excellent parallel processing for web workloads
- **Memory bandwidth**: High throughput for data-intensive operations
- **Cost efficiency**: Better performance per dollar compared to alternatives

**Network Configuration:**
- **Security Groups**: HTTP (80), HTTPS (443), SSH (22), Rails (3000)
- **Elastic IP**: Optional for consistent external access
- **Enhanced Networking**: Enabled for better packet processing

## Performance Characteristics

### Expected RPS by Endpoint

| Endpoint | Description | Expected RPS (m7a.large) | Bottleneck |
|----------|-------------|-------------------------|------------|
| `/ping` | Ultra-minimal | 15,000 - 20,000 | Network I/O |
| `/hello` | Simple text | 12,000 - 18,000 | Rails overhead |
| `/json` | JSON response | 8,000 - 12,000 | JSON serialization |
| `/data` | Data processing | 3,000 - 6,000 | CPU computation |
| `/health` | System metrics | 2,000 - 4,000 | File I/O + CPU |

### Scaling Characteristics

**Vertical Scaling** (Larger instance types):
- **CPU cores**: Linear scaling up to available cores
- **Memory**: Diminishing returns beyond 8GB for this workload
- **Network**: Improves with enhanced networking

**Horizontal Scaling** (Load balancer + multiple instances):
- **Linear scaling** with proper session management
- **Load balancer**: AWS ALB or NLB recommended
- **Health checks**: Use `/health` endpoint

## Benchmarking Tools Architecture

### 1. wrk (Recommended)

```
wrk process
├── Event loop (epoll/kqueue)
├── Thread pool (configurable)
├── HTTP/1.1 connection pooling
└── Lua scripting support
```

**Advantages:**
- Modern async I/O for accurate high-load testing
- Low resource usage on client side
- Detailed latency statistics
- Scriptable for complex scenarios

### 2. Apache Bench (ab)

```
ab process
├── Single-threaded with select()
├── HTTP/1.0 keep-alive
└── Simple statistics
```

**Advantages:**
- Simple and widely available
- Good for basic testing
- Easy to interpret results

**Limitations:**
- Single-threaded (doesn't scale with client cores)
- Less accurate under high load

### 3. Siege

```
siege process
├── Multi-threaded design
├── Transaction logging
└── Realistic user simulation
```

**Advantages:**
- Simulates realistic user patterns
- Good for endurance testing
- Transaction-based metrics

## Memory Architecture

### Ruby Memory Management

```
Ruby Process Memory Layout:
├── Heap (Ruby objects)
│   ├── Object slots
│   ├── String memory
│   └── Array/Hash storage
├── Stack (method calls)
├── Code cache (bytecode)
└── Native extensions
```

**Optimizations:**
- **Preloaded application**: Shared memory between workers
- **Copy-on-write**: Efficient memory usage with forked workers
- **Garbage collection**: Tuned for web workload patterns

### System Memory Usage

```
Typical Memory Distribution (8GB instance):
├── OS + Kernel:           1.5 GB
├── Ruby workers (4x):     2.0 GB (500MB each)
├── Puma master:          200 MB
├── System tools:          100 MB
├── Buffers/Cache:        3.0 GB
└── Available:            1.2 GB
```

## Network Architecture

### TCP Connection Handling

```
Network Flow:
Client → AWS Network → EC2 Instance → iptables → TCP Stack → Puma → Rails

Optimizations:
├── TCP window scaling
├── TCP fast open (where supported)
├── Connection pooling
├── Keep-alive optimization
└── Buffer size tuning
```

### Request Processing Flow

```
1. TCP connection established
2. HTTP request parsing
3. Rails routing
4. Controller action dispatch
5. Response generation
6. HTTP response transmission
7. Connection reuse or close
```

## Monitoring Architecture

### System-Level Monitoring

```bash
# CPU monitoring
htop, top, iostat -x 1

# Memory monitoring
free -h, vmstat 1

# Network monitoring
ss -tuln, netstat -i, iftop

# Disk I/O
iostat -x 1, iotop
```

### Application-Level Monitoring

```bash
# Puma process monitoring
ps aux | grep puma

# Rails logs
tail -f log/production.log

# Request metrics
Custom middleware + /health endpoint
```

### AWS CloudWatch Integration

```
Metrics:
├── CPU Utilization
├── Network In/Out
├── Memory Utilization (with CloudWatch agent)
├── Custom Application Metrics
└── Alarm Configuration
```

## Security Architecture

### Network Security

```
Security Layers:
├── AWS Security Groups (Instance-level firewall)
├── Ubuntu UFW (Host-level firewall)
├── Rails security features (CSRF, XSS protection)
└── Puma request filtering
```

### Application Security

```ruby
# Rails security features enabled:
- CSRF protection (disabled for API endpoints)
- XSS protection
- Content Security Policy headers
- Modern browser requirements
- Request forgery protection
```

## Deployment Architecture

### Container Option (Docker)

```dockerfile
FROM ruby:3.2.0-alpine
WORKDIR /app
COPY Gemfile* ./
RUN bundle install --deployment --without development test
COPY . .
EXPOSE 3000
CMD ["rails", "server", "-e", "production", "-b", "0.0.0.0"]
```

### Traditional Deployment

```bash
# Direct on EC2
1. System setup (setup_ubuntu.sh)
2. Application deployment (git clone + bundle install)
3. Configuration (environment variables)
4. Service startup (systemd or direct)
5. Monitoring setup (benchmark scripts)
```

## Performance Tuning Strategy

### 1. Application Level
- **Production environment**: Disable development features
- **Caching strategy**: Memory store for fast access
- **Logging optimization**: Minimal logging for performance
- **Asset optimization**: Precompiled assets

### 2. Server Level
- **Worker process count**: Match CPU cores
- **Thread count**: Balance concurrency vs memory
- **Memory management**: Proper garbage collection tuning
- **Connection handling**: Optimize keepalive settings

### 3. System Level
- **Kernel parameters**: Network stack optimization
- **File descriptors**: Increase limits for high concurrency
- **Swap configuration**: Optimize for memory pressure
- **CPU affinity**: Pin workers to specific cores (advanced)

### 4. Infrastructure Level
- **Instance type selection**: Balance CPU/memory/network
- **Placement groups**: For multi-instance deployments
- **Enhanced networking**: Enable for better packet processing
- **EBS optimization**: For I/O-intensive workloads

## Troubleshooting Guide

### Common Performance Issues

1. **Low RPS with high CPU**: Thread pool exhaustion
   - **Solution**: Increase `RAILS_MAX_THREADS`

2. **Memory growth**: Memory leaks or inefficient GC
   - **Solution**: Monitor with `memory_profiler`, tune GC

3. **High latency**: Database or I/O bottlenecks
   - **Solution**: Add connection pooling, optimize queries

4. **Connection timeouts**: Network or application overload
   - **Solution**: Increase system limits, scale horizontally

This architecture provides a solid foundation for accurate Rails performance benchmarking on AMD-powered AWS infrastructure while maintaining clarity and reproducibility.