# Quick Start Guide

## For AMD Solutions Architects

This is a simple Ruby on Rails benchmark application optimized for AWS EC2 AMD instances (M7A/M8A).

## 🚀 One-Command Setup

### Option 1: Clone and Run (Recommended)

```bash
# On your AWS EC2 AMD instance (Ubuntu 24.04)
git clone https://github.com/your-username/rails-benchmark-amd.git
cd rails-benchmark-amd
chmod +x setup_ubuntu.sh
sudo ./setup_ubuntu.sh

# After setup completes:
source ~/.bashrc
bundle install

# NEW: Auto-optimize for your instance (utilizes all CPU cores!)
chmod +x optimize_for_instance.sh
./optimize_for_instance.sh

# Start optimized server:
source .env
bundle exec puma &

# Run optimized benchmark (uses all cores):
./benchmark_optimized.sh
```

### Option 2: Docker (If Docker is available)

```bash
git clone https://github.com/your-username/rails-benchmark-amd.git
cd rails-benchmark-amd
docker-compose up -d

# Wait for container to start, then:
docker exec -it rails-benchmark-amd_rails-benchmark_1 ./benchmark_detailed.sh
```

## 📊 Quick Test

```bash
# Test endpoints
curl http://localhost:3000/hello    # Simple text
curl http://localhost:3000/json     # JSON response
curl http://localhost:3000/health   # Health check

# Quick RPS test
wrk -t4 -c50 -d10s http://localhost:3000/hello
```

## 🎯 Expected Results (After Optimization)

**On m7a.large (2 vCPU, 8GB RAM):**
- `/hello`: 12,000-18,000 RPS
- `/json`: 8,000-12,000 RPS
- `/data`: 3,000-6,000 RPS

**On m7a.xlarge (4 vCPU, 16GB RAM):**
- `/hello`: 25,000-35,000 RPS
- `/json`: 15,000-25,000 RPS
- `/data`: 8,000-15,000 RPS

**On m8a.2xlarge (8 vCPU, 32GB RAM) - OPTIMIZED:**
- `/hello`: 50,000-70,000 RPS 🚀
- `/json`: 30,000-45,000 RPS 🚀
- `/data`: 15,000-25,000 RPS 🚀

> **Note:** The optimization script automatically configures your application to use **ALL CPU cores** for maximum performance!

## 📁 Repository Structure

```
rails-benchmark-amd/
├── README.md              # Detailed documentation
├── QUICKSTART.md          # This file
├── ARCHITECTURE.md        # Technical details
├── setup_ubuntu.sh        # Ubuntu setup script
├── optimize_for_instance.sh   # NEW: Auto-optimization script
├── benchmark_detailed.sh  # Comprehensive benchmark suite
├── benchmark_optimized.sh # NEW: Instance-optimized benchmarks
├── Gemfile                # Ruby dependencies
├── config.ru              # Rack configuration
├── Dockerfile             # Container setup
├── docker-compose.yml     # Multi-container setup
├── app/                   # Rails application
│   └── controllers/
│       ├── application_controller.rb
│       └── home_controller.rb
└── config/                # Rails configuration
    ├── application.rb
    ├── routes.rb
    ├── puma.rb            # Auto-optimized configuration
    └── environments/
        ├── development.rb
        └── production.rb
```

## 🔧 Customization

### Instance Size Optimization

**For m7a.xlarge (4 vCPU):**
```bash
export WEB_CONCURRENCY=4
export RAILS_MAX_THREADS=16
```

**For m7a.2xlarge (8 vCPU):**
```bash
export WEB_CONCURRENCY=8
export RAILS_MAX_THREADS=16
```

### Custom Benchmark

```bash
# Test specific endpoint
wrk -t8 -c200 -d30s http://localhost:3000/your-endpoint

# Test with different load
./benchmark_detailed.sh http://your-instance-ip:3000
```

## 🆘 Troubleshooting

**Application not starting:**
```bash
source ~/.bashrc
which ruby  # Should show rbenv version
bundle install
```

**Permission errors:**
```bash
sudo chown -R ubuntu:ubuntu /home/ubuntu/rails-benchmark-amd
chmod +x *.sh
```

**Port in use:**
```bash
sudo lsof -i :3000
sudo kill -9 <PID>
```

## 📞 Need Help?

1. Check logs: `tail -f log/production.log`
2. Verify system: `./setup_ubuntu.sh` (safe to run multiple times)
3. Test health: `curl http://localhost:3000/health`

## 🎯 Ready for Production?

See the full [README.md](README.md) for production deployment, monitoring, and optimization details.