# Puma configuration for Rails Benchmark App
# Optimized for AMD EPYC / AWS EC2 AMD instances (Puma 6+)

app_root = File.expand_path("..", __dir__)

# Number of worker processes (override with WEB_CONCURRENCY env var)
workers ENV.fetch("WEB_CONCURRENCY") { 4 }

# Thread count per worker
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 8 }
threads threads_count, threads_count

# Preload the app for better memory usage and faster worker boot
preload_app!

# Port and environment
port        ENV.fetch("PORT") { 3000 }
environment ENV.fetch("RAILS_ENV") { "production" }

# Bind to all interfaces
bind "tcp://0.0.0.0:#{ENV.fetch("PORT") { 3000 }}"

# Logging (relative to app root)
FileUtils.mkdir_p "#{app_root}/log"
FileUtils.mkdir_p "#{app_root}/tmp/pids"
stdout_redirect "#{app_root}/log/puma.stdout.log", "#{app_root}/log/puma.stderr.log", true

# PID and state files
pidfile   "#{app_root}/tmp/pids/puma.pid"
state_path "#{app_root}/tmp/pids/puma.state"

# Reconnect DB on worker boot
on_worker_boot do
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
end

# Allow puma to be restarted by `rails restart`
plugin :tmp_restart

# Timeouts
worker_timeout      60
worker_boot_timeout 60
