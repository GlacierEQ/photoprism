# syntax=docker/dockerfile:1.4

# Define build arguments
ARG GO_VERSION=1.21
ARG NODE_VERSION=18
ARG DEBIAN_VERSION=bookworm
ARG PHOTOPRISM_VERSION=231226

# Base build stage
FROM golang:${GO_VERSION}-${DEBIAN_VERSION} AS base-build

# Build arguments
ARG TARGETARCH
ARG DEBIAN_FRONTEND=noninteractive
ARG PHOTOPRISM_VERSION

# Build environment
ENV CGO_ENABLED=1 \
    GOOS=linux \
    GOARCH=$TARGETARCH \
    DEBIAN_FRONTEND=noninteractive

# Install base dependencies
RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt-get install -y --no-install-recommends -o Dpkg::Options::="--force-confnew" \
        make build-essential pkg-config \
        libheif-dev libvips-dev \
        && rm -rf /var/lib/apt/lists/*

RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt-get install -y --no-install-recommends -o Dpkg::Options::="--force-confnew" \
        libheif1 libvips42 \
        ca-certificates curl tzdata \
        && rm -rf /var/lib/apt/lists/*


# Go build stage
FROM base-build AS go-build

# Copy Go source files
WORKDIR /build/photoprism
COPY go.mod go.sum ./
COPY cmd cmd/
COPY pkg pkg/
COPY internal internal/

# Build the application
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    make build-go

# Node.js build stage
FROM node:${NODE_VERSION}-${DEBIAN_VERSION}-slim AS node-build

WORKDIR /build/frontend
COPY frontend/package*.json ./

# Install dependencies
RUN --mount=type=cache,target=/root/.npm \
    npm ci --no-audit

# Copy frontend source files
COPY frontend/ ./

# Build frontend assets
RUN npm run build

# Runtime stage
FROM debian:${DEBIAN_VERSION}-slim AS runtime

# Runtime arguments
ARG TARGETARCH
ARG DEBIAN_FRONTEND=noninteractive
ARG PHOTOPRISM_VERSION

# Runtime environment variables
ENV PHOTOPRISM_VERSION=${PHOTOPRISM_VERSION} \
    PHOTOPRISM_ARCH=${TARGETARCH} \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    DEBIAN_FRONTEND=noninteractive

# Install runtime dependencies
RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt-get install -y --no-install-recommends \
        libheif1 libvips42 \
        ca-certificates curl tzdata \
        git \
        && rm -rf /var/lib/apt/lists/*

# Install podman-compose only if PODMAN_ENABLED is set
ARG PODMAN_ENABLED=false
RUN if [ "$PODMAN_ENABLED" = "true" ]; then pip3 install podman-compose; apt-get install -y podman; fi

# Create PhotoPrism directories
RUN mkdir -p \
        /photoprism/bin \
        /photoprism/assets \
        /photoprism/storage/cache \
        /photoprism/storage/config \
        /photoprism/storage/originals \
        /photoprism/storage/import \
        /photoprism/storage/sidecar

# Copy binaries and assets
COPY --from=go-build /build/photoprism/photoprism /photoprism/bin/
COPY --from=node-build /build/frontend/dist /photoprism/assets/static
COPY --from=node-build /build/frontend/dist/build.json /photoprism/assets/static/build.json
COPY assets /photoprism/assets
COPY scripts /photoprism/scripts

# Set permissions
RUN chmod -R 777 /photoprism/storage

# Set working directory
WORKDIR /photoprism

# Expose ports
EXPOSE 2342 2343

# Configure volumes
VOLUME [ "/photoprism/storage" ]

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -f http://localhost:2342/api/v1/status || exit 1

# Set entrypoint
ENTRYPOINT ["/photoprism/scripts/entrypoint.sh"]
CMD ["start"]
