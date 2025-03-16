#!/bin/bash
# PhotoPrism2 Docker Image Optimization Script
# Optimizes Docker images for production use

set -eo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_FILE="${PROJECT_ROOT}/build/optimize-$(date +%Y%m%d-%H%M%S).log"
TEMP_DIR=$(mktemp -d)

# Create build directory if it doesn't exist
mkdir -p "$(dirname "${LOG_FILE}")"

# Default options
IMAGE_NAME="${IMAGE_NAME:-photoprism2}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
OUTPUT_TAG="${OUTPUT_TAG:-${IMAGE_TAG}-optimized}"
COMPRESS_LEVEL="${COMPRESS_LEVEL:-9}"
REMOVE_DOCS="${REMOVE_DOCS:-true}"
REMOVE_DEV_DEPS="${REMOVE_DEV_DEPS:-true}"
SQUASH_LAYERS="${SQUASH_LAYERS:-true}"
OPTIMIZE_SIZE="${OPTIMIZE_SIZE:-true}"
SECURITY_SCAN="${SECURITY_SCAN:-true}"
CLEANUP="${CLEANUP:-true}"

# Output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
  echo -e "${2:-$NC}[$(date '+%Y-%m-%d %H:%M:%S')] [$1]${NC} ${3:-}" | tee -a "$LOG_FILE"
}

# Show help
show_help() {
  echo "PhotoPrism2 Docker Image Optimization Script"
  echo ""
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  --image NAME         Source image name (default: photoprism2)"
  echo "  --tag TAG            Source image tag (default: latest)"
  echo "  --output-tag TAG     Output image tag (default: [TAG]-optimized)"
  echo "  --compress LEVEL     Compression level (1-9, default: 9)"
  echo "  --skip-docs          Skip removing documentation (default: removed)"
  echo "  --keep-dev-deps      Keep development dependencies (default: removed)"
  echo "  --no-squash          Skip squashing layers (default: squashed)"
  echo "  --skip-size-opt      Skip size optimizations (default: optimized)"
  echo "  --skip-security      Skip security scanning (default: scanned)"
  echo "  --no-cleanup         Skip cleanup on exit (default: cleaned up)"
  echo "  --help               Show this help message"
  echo ""
  exit 0
}

# Parse command line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --image)
        IMAGE_NAME="$2"
        shift 2
        ;;
      --tag)
        IMAGE_TAG="$2"
        shift 2
        ;;
      --output-tag)
        OUTPUT_TAG="$2"
        shift 2
        ;;
      --compress)
        COMPRESS_LEVEL="$2"
        shift 2
        ;;
      --skip-docs)
        REMOVE_DOCS="false"
        shift
        ;;
      --keep-dev-deps)
        REMOVE_DEV_DEPS="false"
        shift
        ;;
      --no-squash)
        SQUASH_LAYERS="false"
        shift
        ;;
      --skip-size-opt)
        OPTIMIZE_SIZE="false"
        shift
        ;;
      --skip-security)
        SECURITY_SCAN="false"
        shift
        ;;
      --no-cleanup)
        CLEANUP="false"
        shift
        ;;
      --help)
        show_help
        ;;
      *)
        log "ERROR" "$RED" "Unknown option: $1"
        show_help
        ;;
    esac
  done
}

# Cleanup on exit
cleanup() {
  if [ "$CLEANUP" = "true" ]; then
    log "INFO" "$BLUE" "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
    log "INFO" "$BLUE" "Cleanup complete"
  else
    log "INFO" "$BLUE" "Skipping cleanup, temporary files remain at: $TEMP_DIR"
  fi
}

# Set cleanup trap
trap cleanup EXIT

# Check Docker installation
check_docker() {
  log "INFO" "$BLUE" "Checking Docker installation..."

  if ! command -v docker &> /dev/null; then
    log "ERROR" "$RED" "Docker is not installed or not in PATH"
    exit 1
  fi

  log "INFO" "$BLUE" "Docker is installed: $(docker --version)"

  # Check for Docker buildx
  if ! docker buildx version &> /dev/null; then
    log "WARN" "$YELLOW" "Docker buildx is not available. Some optimizations will be skipped."
  fi
}

# Check if image exists
check_image() {
  log "INFO" "$BLUE" "Checking if image ${IMAGE_NAME}:${IMAGE_TAG} exists..."

  if ! docker image inspect "${IMAGE_NAME}:${IMAGE_TAG}" &> /dev/null; then
    log "ERROR" "$RED" "Image ${IMAGE_NAME}:${IMAGE_TAG} does not exist"
    exit 1
  fi

  # Get image size before optimization
  IMAGE_SIZE_BEFORE=$(docker image inspect "${IMAGE_NAME}:${IMAGE_TAG}" --format='{{.Size}}')
  IMAGE_SIZE_BEFORE_HUMAN=$(numfmt --to=iec-i --suffix=B --format="%.2f" "$IMAGE_SIZE_BEFORE")

  log "INFO" "$BLUE" "Found image ${IMAGE_NAME}:${IMAGE_TAG}, size: $IMAGE_SIZE_BEFORE_HUMAN"
}

# Export and analyze image
analyze_image() {
  log "INFO" "$BLUE" "Analyzing image structure..."

  # Export image history
  docker history --no-trunc "${IMAGE_NAME}:${IMAGE_TAG}" > "${TEMP_DIR}/image_history.txt"

  # Export image config
  docker inspect "${IMAGE_NAME}:${IMAGE_TAG}" > "${TEMP_DIR}/image_config.json"

  # Analyze layers for optimization opportunities
  log "INFO" "$BLUE" "Identifying optimization opportunities..."

  # Check for large layers
  LARGE_LAYERS=$(grep -E '[0-9]+(.[0-9]+)? MB' "${TEMP_DIR}/image_history.txt" | wc -l)

  # Check for many small layers
  SMALL_LAYERS=$(grep -E '[0-9]+(.[0-9]+)? kB' "${TEMP_DIR}/image_history.txt" | wc -l)

  log "INFO" "$BLUE" "Analysis complete. Found $LARGE_LAYERS large layers and $SMALL_LAYERS small layers."

  if [ "$LARGE_LAYERS" -gt 3 ]; then
    log "INFO" "$YELLOW" "Image has several large layers that could benefit from optimization."
  fi

  if [ "$SMALL_LAYERS" -gt 10 ]; then
    log "INFO" "$YELLOW" "Image has many small layers that could benefit from squashing."
  fi
}

# Create optimization Dockerfile
create_optimization_dockerfile() {
  log "INFO" "$BLUE" "Creating optimization Dockerfile..."

  cat > "${TEMP_DIR}/Dockerfile.optimize" << EOF
# Optimization Dockerfile for PhotoPrism2
FROM ${IMAGE_NAME}:${IMAGE_TAG} as source

# Intermediate stage for size optimizations
FROM source as optimizer
USER root

# Run optimizations to reduce image size
RUN set -ex && \\
    mkdir -p /tmp/optimization
EOF

  # Add size optimization commands if enabled
  if [ "$OPTIMIZE_SIZE" = "true" ]; then
    cat >> "${TEMP_DIR}/Dockerfile.optimize" << EOF

# Remove package manager caches
RUN set -ex && \\
    if command -v apt-get >/dev/null; then \\
        apt-get clean && \\
        rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*; \\
    elif command -v apk >/dev/null; then \\
        rm -rf /var/cache/apk/*; \\
    elif command -v yum >/dev/null; then \\
        yum clean all && \\
        rm -rf /var/cache/yum; \\
    fi
EOF
  fi

  # Add documentation removal if enabled
  if [ "$REMOVE_DOCS" = "true" ]; then
    cat >> "${TEMP_DIR}/Dockerfile.optimize" << EOF

# Remove documentation files
RUN set -ex && \\
    find /usr/share/doc -depth -type f ! -name copyright | xargs rm -f || true && \\
    find /usr/share/doc -empty | xargs rmdir || true && \\
    rm -rf /usr/share/man/* /usr/share/info/* /usr/share/doc/* \\
           /var/cache/* /var/log/* /tmp/* /var/tmp/* || true
EOF
  fi

  # Remove development dependencies if enabled
  if [ "$REMOVE_DEV_DEPS" = "true" ]; then
    cat >> "${TEMP_DIR}/Dockerfile.optimize" << EOF

# Remove development packages and tools
RUN set -ex && \\
    if command -v apk >/dev/null; then \\
        apk info --installed | grep -- '-dev' | xargs apk del 2>/dev/null || true; \\
    fi && \\
    rm -rf /usr/local/include/* /usr/include/* || true
EOF
  fi

  # Add final stage
  cat >> "${TEMP_DIR}/Dockerfile.optimize" << EOF

# Final optimized image
FROM scratch
COPY --from=optimizer / /

# Preserve original entry point and cmd
ENTRYPOINT [$(jq -r '.Config.Entrypoint | @sh' "${TEMP_DIR}/image_config.json")]
CMD [$(jq -r '.Config.Cmd | @sh' "${TEMP_DIR}/image_config.json")]

# Add metadata
LABEL org.opencontainers.image.authors="PhotoPrism2 Team <team@photoprism2.org>"
LABEL org.opencontainers.image.created="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
LABEL org.opencontainers.image.source="https://github.com/photoprism/photoprism2"
LABEL org.opencontainers.image.optimization.level="${COMPRESS_LEVEL}"
EOF

  log "INFO" "$GREEN" "Optimization Dockerfile created at ${TEMP_DIR}/Dockerfile.optimize"
}

# Build optimized image
build_optimized_image() {
  log "INFO" "$BLUE" "Building optimized image..."

  BUILD_ARGS=()

  # Add squash option if enabled
  if [ "$SQUASH_LAYERS" = "true" ] && docker buildx version &> /dev/null; then
    BUILD_ARGS+=("--squash")
  fi

  # Add compression level
  BUILD_ARGS+=("--compress")

  # Execute build
  docker build \
    "${BUILD_ARGS[@]}" \
    -t "${IMAGE_NAME}:${OUTPUT_TAG}" \
    -f "${TEMP_DIR}/Dockerfile.optimize" \
    "${TEMP_DIR}" | tee -a "$LOG_FILE"

  # Get size after optimization
  IMAGE_SIZE_AFTER=$(docker image inspect "${IMAGE_NAME}:${OUTPUT_TAG}" --format='{{.Size}}')
  IMAGE_SIZE_AFTER_HUMAN=$(numfmt --to=iec-i --suffix=B --format="%.2f" "$IMAGE_SIZE_AFTER")

  # Calculate size reduction
  SIZE_REDUCTION=$((IMAGE_SIZE_BEFORE - IMAGE_SIZE_AFTER))
  SIZE_REDUCTION_PCT=$(awk "BEGIN {printf \"%.2f\", ($SIZE_REDUCTION / $IMAGE_SIZE_BEFORE) * 100}")
  SIZE_REDUCTION_HUMAN=$(numfmt --to=iec-i --suffix=B --format="%.2f" "$SIZE_REDUCTION")

  log "SUCCESS" "$GREEN" "Optimized image built successfully as ${IMAGE_NAME}:${OUTPUT_TAG}"
  log "INFO" "$GREEN" "Size before: $IMAGE_SIZE_BEFORE_HUMAN"
  log "INFO" "$GREEN" "Size after: $IMAGE_SIZE_AFTER_HUMAN"
  log "INFO" "$GREEN" "Reduction: $SIZE_REDUCTION_HUMAN ($SIZE_REDUCTION_PCT%)"
}

# Security scan optimized image
security_scan() {
  if [ "$SECURITY_SCAN" = "true" ]; then
    log "INFO" "$BLUE" "Performing security scan on optimized image..."

    if command -v trivy &> /dev/null; then
      trivy image --severity HIGH,CRITICAL --no-progress "${IMAGE_NAME}:${OUTPUT_TAG}" | tee -a "$LOG_FILE"
    elif docker info | grep -q "containerd" && docker run --rm aquasec/trivy:latest --help &> /dev/null; then
      docker run --rm \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v "${TEMP_DIR}:/tmp/scan" \
        aquasec/trivy:latest \
        image --severity HIGH,CRITICAL --no-progress "${IMAGE_NAME}:${OUTPUT_TAG}" | tee -a "$LOG_FILE"
    else
      log "WARN" "$YELLOW" "Trivy not available for security scanning. Skipping."
    fi
  else
    log "INFO" "$BLUE" "Security scanning skipped"
  fi
}

# Main function
main() {
  log "INFO" "$BLUE" "===== PhotoPrism2 Docker Image Optimization ====="

  # Parse command line arguments
  parse_args "$@"

  # Check dependencies
  check_docker

  # Check if source image exists
  check_image

  # Analyze image structure
  analyze_image

  # Create optimization Dockerfile
  create_optimization_dockerfile

  # Build optimized image
  build_optimized_image

  # Security scan if enabled
  security_scan

  log "SUCCESS" "$GREEN" "===== Image Optimization Complete ====="
  log "SUCCESS" "$GREEN" "Optimized image: ${IMAGE_NAME}:${OUTPUT_TAG}"
  log "INFO" "$BLUE" "Log file: $LOG_FILE"
}

# Run main with command line arguments
main "$@"
