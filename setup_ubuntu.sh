#!/bin/bash

# Rails Benchmark Application Setup Script
# For Ubuntu 24.04 LTS on AWS EC2 (AMD M7A/M8A instances)
# This script installs Ruby, Rails, and all necessary dependencies

set -e  # Exit on any error

echo "=== Rails Benchmark App Setup for Ubuntu 24.04 ==="
echo "Setting up environment for AWS EC2 AMD instances..."

# Load rbenv into current shell if already installed (safe to run even if not yet installed)
# This ensures rbenv is always in PATH on re-runs of this script
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)" 2>/dev/null || true

# Verify rbenv if already present
if command -v rbenv &>/dev/null; then
    echo "rbenv already available: $(rbenv --version)"
fi

# Update system packages
echo "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Install essential development packages
echo "Installing essential development packages..."
sudo apt install -y \
    build-essential \
    curl \
    git \
    wget \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    unzip \
    vim \
    htop \
    tree

# Install Node.js (required for Rails asset pipeline)
echo "Installing Node.js..."
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Install Yarn (alternative package manager for Node.js)
echo "Installing Yarn..."
curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor | sudo tee /usr/share/keyrings/yarnkey.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/yarnkey.gpg] https://dl.yarnpkg.com/debian stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
sudo apt update && sudo apt install -y yarn

# Install SQLite3 (lightweight database for development)
echo "Installing SQLite3..."
sudo apt install -y sqlite3 libsqlite3-dev

# Install Ruby build dependencies (required before compiling Ruby via rbenv)
# Missing these causes psych, readline, openssl extensions to fail during build
echo "Installing Ruby build dependencies..."
sudo apt-get install -y \
    libreadline-dev \
    libyaml-dev \
    libssl-dev \
    zlib1g-dev \
    libffi-dev \
    libgdbm-dev \
    libncurses5-dev \
    autoconf \
    bison

# Install Ruby using rbenv (Ruby version manager)
echo "Installing rbenv and Ruby..."
if [ ! -d "$HOME/.rbenv" ]; then
    git clone https://github.com/rbenv/rbenv.git ~/.rbenv
    echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
    echo 'eval "$(rbenv init -)"' >> ~/.bashrc
    git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
fi

# Always load rbenv into current shell — whether just installed or already present
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

# Install Ruby 3.2.0
echo "Installing Ruby 3.2.0..."
if ! rbenv versions | grep -q "3.2.0"; then
    rbenv install 3.2.0
    rbenv global 3.2.0
    rbenv rehash
fi

# Source bashrc to ensure rbenv is available
source ~/.bashrc || true
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)" || true

# Update RubyGems and install Bundler
echo "Installing Bundler..."
gem update --system
gem install bundler

# Install Rails
echo "Installing Rails..."
gem install rails -v "~> 7.1.0"

# Install benchmarking and monitoring tools
echo "Installing benchmarking tools..."
sudo apt install -y \
    apache2-utils \
    wrk \
    siege \
    stress-ng \
    sysstat \
    iotop \
    nethogs

# Install and configure Nginx (optional, for production deployment)
echo "Installing Nginx..."
sudo apt install -y nginx
sudo systemctl enable nginx

# Create a simple Nginx configuration for the Rails app
sudo tee /etc/nginx/sites-available/rails-benchmark > /dev/null << 'EOF'
upstream rails_app {
    server 127.0.0.1:3000;
}

server {
    listen 80;
    listen [::]:80;

    server_name _;
    root $HOME/rails-benchmark/public;

    location / {
        try_files $uri $uri/ @rails_app;
    }

    location @rails_app {
        proxy_pass http://rails_app;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_redirect off;
    }

    # Serve static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

# Install system monitoring tools
# iostat/vmstat are in sysstat/procps, netstat in net-tools, ss in iproute2
echo "Installing system monitoring tools..."
sudo apt install -y \
    htop \
    sysstat \
    procps \
    net-tools \
    iproute2 \
    tcpdump

# Set up firewall (allow SSH, HTTP, and custom Rails port)
echo "Configuring UFW firewall..."
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 22
sudo ufw allow 80
sudo ufw allow 443
sudo ufw allow 3000  # Rails development server
sudo ufw --force enable

# Create swap file for better memory management (important for small instances)
if [ ! -f /swapfile ]; then
    echo "Creating swap file..."
    sudo fallocate -l 2G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
fi

# Docker intentionally not installed:
# perf hardware PMU events do not work inside Docker containers.
# All benchmarking runs directly on bare-metal or EC2 host.

# Create directory for the Rails application
echo "Creating application directory..."
mkdir -p $HOME/rails-benchmark
cd $HOME/rails-benchmark

# Install Ruby gems system-wide dependencies
echo "Installing Ruby gems system dependencies..."
sudo apt install -y \
    libffi-dev \
    libssl-dev \
    libxml2-dev \
    libxslt1-dev \
    libcurl4-openssl-dev \
    libmysqlclient-dev \
    libpq-dev

# Set optimal system configurations for performance
echo "Setting system optimizations..."
sudo tee -a /etc/sysctl.conf > /dev/null << 'EOF'

# Network optimizations for high performance web serving
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_tw_reuse = 1

# File descriptor limits
fs.file-max = 2097152
EOF

# Apply sysctl settings
sudo sysctl -p

# Set ulimit for the current user
echo "Setting user limits..."
sudo tee -a /etc/security/limits.conf > /dev/null << 'EOF'
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 1048576
* hard nproc 1048576
EOF

# Create a simple benchmark script
echo "Creating benchmark script..."
cat > $HOME/rails-benchmark/benchmark.sh << 'EOF'
#!/bin/bash

# Rails Benchmark Script
# Tests various endpoints with different load testing tools

APP_URL="http://localhost:3000"
RESULTS_DIR="$HOME/benchmark-results"

mkdir -p $RESULTS_DIR

echo "=== Rails Benchmark Test Suite ==="
echo "Testing Rails application at: $APP_URL"
echo "Results will be saved to: $RESULTS_DIR"

# Wait for the application to be ready
echo "Checking if Rails app is running..."
for i in {1..30}; do
    if curl -s $APP_URL/health > /dev/null; then
        echo "Rails app is responding!"
        break
    fi
    echo "Waiting for Rails app... ($i/30)"
    sleep 2
done

# Test 1: Apache Bench (ab) - Simple GET requests
echo "Running Apache Bench test..."
ab -n 10000 -c 50 -g $RESULTS_DIR/ab_test.gnuplot $APP_URL/hello > $RESULTS_DIR/ab_results.txt 2>&1

# Test 2: wrk - Modern HTTP benchmarking tool
echo "Running wrk test..."
wrk -t12 -c400 -d30s --latency $APP_URL/hello > $RESULTS_DIR/wrk_results.txt 2>&1

# Test 3: JSON endpoint test
echo "Running JSON endpoint test..."
wrk -t8 -c200 -d15s $APP_URL/json > $RESULTS_DIR/json_wrk_results.txt 2>&1

# Test 4: Data processing endpoint test
echo "Running data processing endpoint test..."
wrk -t4 -c100 -d15s $APP_URL/data > $RESULTS_DIR/data_wrk_results.txt 2>&1

# Test 5: Siege test
echo "Running Siege test..."
siege -c50 -t30s $APP_URL/hello > $RESULTS_DIR/siege_results.txt 2>&1

echo "Benchmark complete! Results saved to $RESULTS_DIR"
echo "Summary:"
echo "========"
grep "Requests per second" $RESULTS_DIR/ab_results.txt || echo "Ab results not found"
grep "Req/Sec" $RESULTS_DIR/wrk_results.txt || echo "Wrk results not found"
EOF

chmod +x $HOME/rails-benchmark/benchmark.sh

# Create a system information script
cat > $HOME/system_info.sh << 'EOF'
#!/bin/bash

echo "=== System Information ==="
echo "Date: $(date)"
echo "Hostname: $(hostname)"
echo "Uptime: $(uptime)"
echo ""

echo "=== Hardware Info ==="
echo "CPU: $(lscpu | grep 'Model name' | cut -d: -f2 | xargs)"
echo "CPU Cores: $(nproc)"
echo "Memory: $(free -h | grep Mem | awk '{print $2}')"
echo "Disk: $(df -h / | awk 'NR==2{print $2}')"
echo ""

echo "=== Network Info ==="
echo "Private IP: $(hostname -I | awk '{print $1}')"
echo "Public IP: $(curl -s ifconfig.me 2>/dev/null || echo 'Not available')"
echo ""

echo "=== Instance Info (if on AWS) ==="
curl -s http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null && echo "" || echo "Not on AWS"
curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone 2>/dev/null && echo "" || echo ""

echo "=== Ruby & Rails Info ==="
which ruby && ruby -v
which rails && rails -v
which bundler && bundler -v
echo ""
EOF

chmod +x $HOME/system_info.sh

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "Ruby version: $(ruby -v 2>/dev/null || echo 'Ruby installed — open a new shell to use it')"
echo "Rails version: $(rails -v 2>/dev/null || echo 'Rails installed — open a new shell to use it')"
echo ""
echo "Next steps:"
echo "1. Open a NEW shell (or reconnect via SSH) — rbenv will be in PATH automatically"
echo "2. cd into the repo directory (e.g. ~/rails-benchmark-amd)"
echo "3. Run 'bundle install'"
echo "4. Run 'bundle exec rails db:create db:migrate db:seed'"
echo "5. Run 'export RAILS_ENV=production SECRET_KEY_BASE=\$(bundle exec rails secret)'"
echo "6. Run 'bundle exec puma -e production -p 3000 -b 0.0.0.0 &' to start the server"
echo "7. Run 'wrk -t4 -c100 -d30s http://localhost:3000/hello' to benchmark"
echo ""
echo "See README.md for full usage instructions."