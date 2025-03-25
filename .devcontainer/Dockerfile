# syntax=docker/dockerfile:1.4

# Build arguments with explicit versions
ARG PHOTOPRISM_VERSION=preview
ARG GO_VERSION=1.21
ARG NODE_VERSION=18
ARG PYTHON_VERSION=3.11.5

# Base stage with core dependencies
FROM photoprism/photoprism:${PHOTOPRISM_VERSION} AS base

# Development tools stage with optimized layer caching
FROM base AS devtools
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt-get install -y --no-install-recommends \
    git=1:2.* \
    golang=${GO_VERSION}* \
    nodejs=${NODE_VERSION}* \
    npm \
    python3=${PYTHON_VERSION}* \
    python3-pip \
    redis-tools \
    mariadb-client \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

# Go development stage
FROM devtools AS gobuild
ENV GOPATH=/go \
    PATH=$GOPATH/bin:/usr/local/go/bin:$PATH \
    CGO_ENABLED=1
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

# Node.js development stage
FROM gobuild AS nodebuild
COPY package*.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci

# Python development stage
FROM nodebuild AS pythonbuild
COPY pkg/face/requirements.txt /tmp/
RUN --mount=type=cache,target=/root/.cache/pip \
    pip3 install -r /tmp/requirements.txt

# Final stage
FROM pythonbuild AS final

# Copy configuration and scripts
COPY .devcontainer/supervisor/app.conf /etc/supervisor/conf.d/supervisord.conf
COPY .devcontainer/startup.sh /usr/local/bin/
COPY scripts/test-docker-system.sh /usr/local/bin/

# Setup directories and permissions
RUN mkdir -p /workspace/scripts \
    /photoprism/{import,originals,storage} \
    /var/log/supervisor \
    /var/run && \
    chmod -R 777 /workspace \
        /photoprism \
        /var/log/supervisor \
        /var/run && \
    chmod +x /usr/local/bin/startup.sh \
        /usr/local/bin/test-docker-system.sh

# Create face recognition service wrapper
RUN echo '#!/bin/bash\ncd /workspace/pkg/face && exec python3 -m face_recognition_service' > /usr/local/bin/face-recognition-service && \
    chmod +x /usr/local/bin/face-recognition-service

# Environment configuration
ENV PHOTOPRISM_IMPORT_PATH="/photoprism/import" \
    PHOTOPRISM_ORIGINALS_PATH="/photoprism/originals" \
    PHOTOPRISM_STORAGE_PATH="/photoprism/storage" \
    PHOTOPRISM_DATABASE_DRIVER="mysql" \
    PHOTOPRISM_TEST_DRIVER="sqlite" \
    PYTHONPATH="/workspace/pkg/face:${PYTHONPATH}" \
    NODE_ENV="development"

# Security scanning
FROM aquasec/trivy:latest AS security-scan
COPY --from=final / /
RUN trivy filesystem --exit-code 1 --severity HIGH,CRITICAL /

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -f http://localhost:2342/api/v1/status || exit 1

WORKDIR /workspace

# Set default command
CMD ["/usr/local/bin/startup.sh"]
