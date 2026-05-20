# Rails Benchmark Application Dockerfile
# Optimized for AMD64 architecture

FROM ruby:3.2.0-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    linux-headers \
    git \
    postgresql-dev \
    sqlite-dev \
    libxml2-dev \
    libxslt-dev \
    curl-dev \
    nodejs \
    yarn

WORKDIR /app

# Copy Gemfile and install gems
COPY Gemfile Gemfile.lock ./
RUN bundle config --global frozen 1 && \
    bundle install --deployment --without development test

# Production stage
FROM ruby:3.2.0-alpine AS production

# Install runtime dependencies
RUN apk add --no-cache \
    sqlite \
    libxml2 \
    libxslt \
    curl \
    nodejs \
    tzdata

# Create app user
RUN addgroup -g 1000 app && \
    adduser -u 1000 -G app -s /bin/sh -D app

WORKDIR /app

# Copy application
COPY --from=builder /app .
COPY . .

# Set proper ownership
RUN chown -R app:app /app

# Create necessary directories
RUN mkdir -p tmp/pids tmp/cache tmp/sockets log && \
    chown -R app:app tmp log

USER app

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# Default command
CMD ["bundle", "exec", "puma", "-e", "production", "-p", "3000", "-b", "0.0.0.0"]