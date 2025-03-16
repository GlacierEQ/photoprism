# PhotoPrism2 Dockerfile
# Multi-stage build for optimized production container with enhanced terminal support

# Build arguments
ARG NODE_VERSION=16
ARG GO_VERSION=1.19
ARG ALPINE_VERSION=3.17

# Build stage for frontend
FROM node:${NODE_VERSION}-alpine AS frontend-builder
WORKDIR /app

# Add build metadata
ARG BUILD_DATE
ARG VERSION
ARG VCS_REF

LABEL org.label-schema.build-date=${BUILD_DATE} \
      org.label-schema.name="PhotoPrism2 Frontend" \
      org.label-schema.description="PhotoPrism2 Frontend Assets" \
      org.label-schema.vcs-ref=${VCS_REF} \
      org.label-schema.vcs-url="https://github.com/photoprism/photoprism2" \
      org.label-schema.version=${VERSION} \
      org.label-schema.schema-version="1.0"

# Install dependencies first (better caching)
COPY frontend/package*.json ./
RUN npm ci --no-audit --no-fund --loglevel error

# Copy and build frontend code
COPY frontend/ ./
RUN npm run build && npm prune --production

# Build stage for backend
FROM golang:${GO_VERSION}-alpine AS backend-builder
WORKDIR /app

# Add build metadata
ARG BUILD_DATE
ARG VERSION
ARG VCS_REF

LABEL org.label-schema.build-date=${BUILD_DATE} \
      org.label-schema.name="PhotoPrism2 Backend" \
      org.label-schema.description="PhotoPrism2 Backend Binary" \
      org.label-schema.vcs-ref=${VCS_REF} \
      org.label-schema.vcs-url="https://github.com/photoprism/photoprism2" \
      org.label-schema.version=${VERSION} \
      org.label-schema.schema-version="1.0"

# Install build dependencies
RUN apk --no-cache add git gcc musl-dev

# Download dependencies first (better caching)
COPY backend/go.mod backend/go.sum ./
RUN go mod download

# Copy and build backend code with security flags
COPY backend/ ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w -X main.Version=${VERSION} -X main.BuildDate=${BUILD_DATE}" \
    -o photoprism2 ./cmd/photoprism2

# Final minimal stage
FROM alpine:${ALPINE_VERSION} AS final

# Add build metadata
ARG BUILD_DATE
ARG VERSION
ARG VCS_REF

LABEL org.opencontainers.image.created=${BUILD_DATE} \
      org.opencontainers.image.title="PhotoPrism2" \
      org.opencontainers.image.description="PhotoPrism2 Application" \
      org.opencontainers.image.source="https://github.com/photoprism/photoprism2" \
      org.opencontainers.image.revision=${VCS_REF} \
      org.opencontainers.image.version=${VERSION} \
      org.opencontainers.image.vendor="PhotoPrism" \
      org.opencontainers.image.authors="PhotoPrism2 Team <team@photoprism2.org>" \
      org.opencontainers.image.licenses="MIT"

# Install runtime dependencies with enhanced terminal support
RUN apk --no-cache add \
    ca-certificates \
    tzdata \
    exiftool \
    ffmpeg \
    netcat-openbsd \
    curl \
    bash \
    tini \
    ncurses \
    shadow \
    util-linux \
    less \
    nano \
    vim \
    bash-completion \
    && rm -rf /var/cache/apk/*

# Configure terminal environment
RUN echo "export PS1='\[\033[1;36m\]photoprism2\[\033[0m\]:\[\033[1;34m\]\w\[\033[0m\]$ '" >> /etc/profile.d/terminal.sh && \
    echo "export TERM=xterm-256color" >> /etc/profile.d/terminal.sh && \
    echo "export EDITOR=nano" >> /etc/profile.d/terminal.sh && \
    echo "alias ls='ls --color=auto'" >> /etc/profile.d/terminal.sh && \
    echo "alias ll='ls -la'" >> /etc/profile.d/terminal.sh && \
    echo "alias l='ls -l'" >> /etc/profile.d/terminal.sh && \
    chmod +x /etc/profile.d/terminal.sh

# Create non-root user with proper terminal settings
RUN addgroup -S appgroup && \
    adduser -S appuser -G appgroup -s /bin/bash && \
    mkdir -p /home/appuser && \
    chown -R appuser:appgroup /home/appuser

# Copy bashrc for better terminal experience
RUN echo 'source /etc/profile.d/terminal.sh' > /home/appuser/.bashrc && \
    echo 'if [ -f /etc/bash_completion ]; then . /etc/bash_completion; fi' >> /home/appuser/.bashrc && \
    echo 'export PATH=$PATH:/app' >> /home/appuser/.bashrc && \
    chown appuser:appgroup /home/appuser/.bashrc

# Set working directory
WORKDIR /app

# Copy built artifacts from previous stages
COPY --from=frontend-builder /app/dist /app/frontend/dist
COPY --from=backend-builder /app/photoprism2 /app/photoprism2
COPY --chown=appuser:appgroup config/ /app/config/

# Copy entrypoint script and health check script
COPY --chown=appuser:appgroup docker-entrypoint.sh /app/
COPY --chown=appuser:appgroup docker/scripts/healthcheck.sh /app/healthcheck.sh
RUN chmod +x /app/docker-entrypoint.sh /app/healthcheck.sh

# Create necessary directories and set permissions
RUN mkdir -p /app/storage/photos /app/storage/thumbnails /app/storage/temp /app/storage/logs \
    && chown -R appuser:appgroup /app/storage

# Switch to non-root user
USER appuser

# Environment variables for terminal
ENV NODE_ENV=production \
    PORT=8000 \
    CONFIG_PATH=/app/config \
    STORAGE_PATH=/app/storage \
    LOG_LEVEL=info \
    TZ=UTC \
    TERM=xterm-256color \
    COLORTERM=truecolor \
    HISTCONTROL=ignoreboth \
    HISTSIZE=1000 \
    HISTFILESIZE=2000 \
    LANG=en_US.UTF-8 \
    SHELL=/bin/bash

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD /app/healthcheck.sh || exit 1

# Use tini as init to handle signals properly
ENTRYPOINT ["/sbin/tini", "--", "/app/docker-entrypoint.sh"]
CMD ["/app/photoprism2"]
