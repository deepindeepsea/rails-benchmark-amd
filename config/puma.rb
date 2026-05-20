# Puma configuration for Rails Benchmark App
# Optimized for AWS EC2 AMD instances

# Number of worker processes
workers ENV.fetch("WEB_CONCURRENCY") { 4 }

# Thread count per worker
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 8 }
threads threads_count, threads_count

# Preload the app for better memory usage and faster worker boot times
preload_app!

# Specifies the rackup file to use
rackup DefaultRackup

# Specifies the port to listen on
port ENV.fetch("PORT") { 3000 }

# Specifies the environment
environment ENV.fetch("RAILS_ENV") { "production" }

# Bind to all interfaces for EC2 access
bind "tcp://0.0.0.0:#{ENV.fetch("PORT") { 3000 }}"

# Logging
stdout_redirect '/home/ubuntu/rails-benchmark/log/puma.stdout.log', '/home/ubuntu/rails-benchmark/log/puma.stderr.log', true

# Process ID file
pidfile '/home/ubuntu/rails-benchmark/tmp/pids/puma.pid'

# State file for restart
state_path '/home/ubuntu/rails-benchmark/tmp/pids/puma.state'

# On worker boot
on_worker_boot do
  # Worker specific setup for Rails 4.1+
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
end

# Allow puma to be restarted by `rails restart` command
plugin :tmp_restart

# Performance tuning
worker_timeout 60
worker_boot_timeout 60

# Preload app for better memory usage
preload_app!

# Memory optimization
nakayoshi_fork if ENV["RAILS_ENV"] == "production"