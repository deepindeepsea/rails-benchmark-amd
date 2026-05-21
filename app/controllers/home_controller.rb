class HomeController < ApplicationController
  def index
    render plain: "Hello World from Rails Benchmark App!"
  end

  def hello
    render plain: "Hello World!"
  end

  def ping
    render plain: "pong"
  end

  def json
    render json: {
      message: "Hello World!",
      timestamp: Time.current.iso8601,
      server: "Rails #{Rails.version}",
      ruby: "Ruby #{RUBY_VERSION}",
      request_id: request.request_id
    }
  end

  def data
    # Simulate some basic data processing
    numbers = (1..100).to_a
    result = {
      sum: numbers.sum,
      average: numbers.sum / numbers.length.to_f,
      count: numbers.length,
      timestamp: Time.current.iso8601,
      server_info: {
        rails_version: Rails.version,
        ruby_version: RUBY_VERSION,
        platform: RUBY_PLATFORM
      }
    }
    render json: result
  end

  def health
    render json: {
      status: "healthy",
      timestamp: Time.current.iso8601,
      uptime: Process.clock_gettime(Process::CLOCK_MONOTONIC),
      memory: get_memory_usage,
      rails_version: Rails.version,
      ruby_version: RUBY_VERSION
    }
  end

  private

  def get_memory_usage
    if File.exist?('/proc/meminfo')
      # Linux memory info
      meminfo = File.read('/proc/meminfo')
      total_match = meminfo.match(/MemTotal:\s+(\d+) kB/)
      free_match = meminfo.match(/MemFree:\s+(\d+) kB/)

      if total_match && free_match
        total_kb = total_match[1].to_i
        free_kb = free_match[1].to_i
        used_kb = total_kb - free_kb

        return {
          total_mb: (total_kb / 1024.0).round(2),
          used_mb: (used_kb / 1024.0).round(2),
          free_mb: (free_kb / 1024.0).round(2),
          usage_percent: ((used_kb.to_f / total_kb) * 100).round(2)
        }
      end
    end

    # Fallback for non-Linux systems
    { message: "Memory info not available on this platform" }
  end
end