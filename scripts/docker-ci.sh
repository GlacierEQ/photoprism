#!/bin/bash
# PhotoPrism2 Docker CI/CD Integration Script
# Automates Docker builds in CI environments with advanced features

set -eo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build/ci"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
LOG_FILE="${BUILD_DIR}/docker-ci-${TIMESTAMP}.log"
ENV_FILE="${PROJECT_ROOT}/.env"
DOCKERFILE="${PROJECT_ROOT}/Dockerfile"

# Create build directory
mkdir -p "${BUILD_DIR}"

# Output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default build arguments
CI_ENV=${CI_ENVIRONMENT_NAME:-"ci"}
CI_COMMIT=${CI_COMMIT_SHA:-$(git rev-parse --short HEAD 2>/dev/null || echo "dev")}
VERSION=$(grep -oP 'version:\s*"\K[^"]+' "${PROJECT_ROOT}/package.json" 2>/dev/null || echo "dev")
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
REGISTRY="${REGISTRY:-docker.io}"
REPOSITORY="${REPOSITORY:-photoprism2}"
IMAGE_NAME="${IMAGE_NAME:-${REPOSITORY}}"
IMAGE_TAG="${IMAGE_TAG:-${CI_COMMIT}}"
CACHE_TAG="${CACHE_TAG:-cache-${CI_COMMIT}}"
CACHE_FROM="${CACHE_FROM:-${REGISTRY}/${REPOSITORY}:cache}"
PLATFORMS="${PLATFORMS:-linux/amd64}"
BUILD_TIMEOUT="${BUILD_TIMEOUT:-3600}"
DOCKER_BUILDKIT="${DOCKER_BUILDKIT:-1}"

# Feature flags
DO_LOGIN="${DO_LOGIN:-false}"
DO_PUSH="${DO_PUSH:-false}"
DO_SCAN="${DO_SCAN:-true}"
DO_MULTI_ARCH="${DO_MULTI_ARCH:-false}"
DO_COLLECT_METRICS="${DO_COLLECT_METRICS:-true}"
DO_PUBLISH_ARTIFACTS="${DO_PUBLISH_ARTIFACTS:-false}"

# Logging function
log() {
  local level=$1
  local message=$2
  local color=$NC

  case $level in
    "INFO") color=$BLUE ;;
    "SUCCESS") color=$GREEN ;;
    "WARN") color=$YELLOW ;;
    "ERROR") color=$RED ;;
  esac

  echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [${level}]${NC} ${message}" | tee -a "$LOG_FILE"
}

# Error handling
handle_error() {
  log "ERROR" "Build failed at line $1"
  log "ERROR" "Check the log file at $LOG_FILE for details"
  notify_failure
  exit 1
}

# Set error trap
trap 'handle_error $LINENO' ERR

# Function to show help
show_help() {
  echo "PhotoPrism2 Docker CI/CD Integration"
  echo ""
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  --registry REGISTRY      Docker registry (default: docker.io)"
  echo "  --repository REPO        Repository name (default: photoprism2)"
  echo "  --tag TAG                Image tag (default: commit hash)"
  echo "  --cache-from IMAGE       Use specified image for cache"
  echo "  --platforms PLATFORMS    Comma-separated list of platforms to build"
  echo "                           (default: linux/amd64)"
  echo "  --dockerfile FILE        Path to Dockerfile (default: ./Dockerfile)"
  echo "  --login                  Log in to Docker registry"
  echo "  --push                   Push images after building"
  echo "  --no-scan                Skip security scanning"
  echo "  --multi-arch             Build multi-architecture images"
  echo "  --timeout SECONDS        Build timeout in seconds (default: 3600)"
  echo "  --no-metrics             Skip collecting build metrics"
  echo "  --publish-artifacts      Publish build artifacts"
  echo "  --help                   Show this help message"
  echo ""
  echo "Environment variables:"
  echo "  REGISTRY                 Same as --registry"
  echo "  REPOSITORY               Same as --repository"
  echo "  IMAGE_TAG                Same as --tag"
  echo "  CACHE_FROM               Same as --cache-from"
  echo "  PLATFORMS                Same as --platforms"
  echo "  DOCKERFILE               Path to Dockerfile"
  echo "  DO_LOGIN                 Set to 'true' to log in to registry"
  echo "  DO_PUSH                  Set to 'true' to push images"
  echo "  DO_SCAN                  Set to 'false' to skip security scanning"
  echo "  DO_MULTI_ARCH            Set to 'true' for multi-architecture builds"
  echo "  BUILD_TIMEOUT            Same as --timeout"
  echo "  DO_COLLECT_METRICS       Set to 'false' to skip metrics collection"
  echo "  DO_PUBLISH_ARTIFACTS     Set to 'true' to publish artifacts"
  echo "  DOCKER_USERNAME          Registry username"
  echo "  DOCKER_PASSWORD          Registry password"
  echo "  DOCKER_BUILDKIT          Enable BuildKit (default: 1)"
  echo ""
  exit 0
}

# Parse command line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --registry)
        REGISTRY="$2"
        shift 2
        ;;
      --repository)
        REPOSITORY="$2"
        IMAGE_NAME="$2"
        shift 2
        ;;
      --tag)
        IMAGE_TAG="$2"
        shift 2
        ;;
      --cache-from)
        CACHE_FROM="$2"
        shift 2
        ;;
      --platforms)
        PLATFORMS="$2"
        shift 2
        ;;
      --dockerfile)
        DOCKERFILE="$2"
        shift 2
        ;;
      --login)
        DO_LOGIN="true"
        shift
        ;;
      --push)
        DO_PUSH="true"
        shift
        ;;
      --no-scan)
        DO_SCAN="false"
        shift
        ;;
      --multi-arch)
        DO_MULTI_ARCH="true"
        shift
        ;;
      --timeout)
        BUILD_TIMEOUT="$2"
        shift 2
        ;;
      --no-metrics)
        DO_COLLECT_METRICS="false"
        shift
        ;;
      --publish-artifacts)
        DO_PUBLISH_ARTIFACTS="true"
        shift
        ;;
      --help)
        show_help
        ;;
      *)
        log "ERROR" "Unknown option: $1"
        show_help
        ;;
    esac
  done
}

# Load environment variables
load_env() {
  if [ -f "$ENV_FILE" ]; then
    log "INFO" "Loading environment variables from $ENV_FILE"
    # shellcheck disable=SC1090
    source "$ENV_FILE"
  else
    log "WARN" "Environment file not found at $ENV_FILE"
  fi
}

# Check for Docker
check_docker() {
  log "INFO" "Checking Docker installation..."

  if ! command -v docker &> /dev/null; then
    log "ERROR" "Docker is not installed or not in PATH"
    exit 1
  fi

  log "INFO" "Docker is installed: $(docker --version)"

  # Set BuildKit
  export DOCKER_BUILDKIT="$DOCKER_BUILDKIT"
  log "INFO" "Docker BuildKit is $([ "$DOCKER_BUILDKIT" = "1" ] && echo "enabled" || echo "disabled")"

  # Check for Docker Buildx if needed
  if [ "$DO_MULTI_ARCH" = "true" ]; then
    if ! docker buildx version &> /dev/null; then
      log "ERROR" "Docker Buildx is required for multi-architecture builds"
      exit 1
    fi
    log "INFO" "Docker Buildx is installed: $(docker buildx version | head -1)"
  fi
}

# Set up registry authentication
setup_registry_auth() {
  if [ "$DO_LOGIN" = "true" ]; then
    log "INFO" "Setting up registry authentication for $REGISTRY..."

    # Check for registry credentials
    if [ -n "${DOCKER_USERNAME:-}" ] && [ -n "${DOCKER_PASSWORD:-}" ]; then
      log "INFO" "Logging in to registry $REGISTRY"
      echo "${DOCKER_PASSWORD}" | docker login "${REGISTRY}" -u "${DOCKER_USERNAME}" --password-stdin
      log "SUCCESS" "Successfully logged in to $REGISTRY"
    else
      log "WARN" "Registry credentials not provided. Some operations may fail."
    fi
  fi
}

# Set up build context
setup_build_context() {
  log "INFO" "Setting up build context..."

  # Create build info file
  BUILD_INFO_FILE="${BUILD_DIR}/build-info.json"
  mkdir -p "$(dirname "$BUILD_INFO_FILE")"

  cat > "$BUILD_INFO_FILE" << EOF
{
  "version": "${VERSION}",
  "buildDate": "${BUILD_DATE}",
  "commit": "${CI_COMMIT}",
  "environment": "${CI_ENV}",
  "registry": "${REGISTRY}",
  "repository": "${REPOSITORY}",
  "imageTag": "${IMAGE_TAG}"
}
EOF

  log "INFO" "Build info written to $BUILD_INFO_FILE"

  # Verify Dockerfile exists
  if [ ! -f "$DOCKERFILE" ]; then
    log "ERROR" "Dockerfile not found at $DOCKERFILE"
    exit 1
  fi

  log "SUCCESS" "Build context setup completed"
}

# Set up BuildKit for multi-architecture builds
setup_buildx() {
  if [ "$DO_MULTI_ARCH" = "true" ]; then
    log "INFO" "Setting up BuildKit for multi-architecture builds..."

    # Check if builder exists and create if needed
    if ! docker buildx inspect photoprism-builder &> /dev/null; then
      log "INFO" "Creating new buildx builder: photoprism-builder"
      docker buildx create --name photoprism-builder --driver docker-container --use
    else
      log "INFO" "Using existing buildx builder: photoprism-builder"
      docker buildx use photoprism-builder
    fi

    # Bootstrap builder
    docker buildx inspect --bootstrap

    log "SUCCESS" "BuildKit setup completed"
  fi
}

# Build the Docker image
build_docker_image() {
  log "INFO" "Building Docker image: ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

  # Start build timestamp
  BUILD_START=$(date +%s)

  # Prepare build arguments
  BUILD_ARGS=(
    "--build-arg" "BUILD_DATE=${BUILD_DATE}"
    "--build-arg" "VERSION=${VERSION}"
    "--build-arg" "VCS_REF=${CI_COMMIT}"
    "--label" "org.opencontainers.image.created=${BUILD_DATE}"
    "--label" "org.opencontainers.image.version=${VERSION}"
    "--label" "org.opencontainers.image.revision=${CI_COMMIT}"
    "--label" "org.opencontainers.image.title=PhotoPrism2"
    "--label" "org.opencontainers.image.vendor=PhotoPrism"
    "--label" "org.opencontainers.image.authors=PhotoPrism Team"
    "--label" "org.opencontainers.image.url=https://github.com/photoprism/photoprism2"
  )

  # Add cache-from if specified
  if [ -n "$CACHE_FROM" ] && [ "$CACHE_FROM" != "none" ]; then
    BUILD_ARGS+=("--cache-from" "$CACHE_FROM")

    # Try to pull cache image for better caching
    docker pull "$CACHE_FROM" || log "WARN" "Could not pull cache image $CACHE_FROM, continuing without it"
  fi

  # Determine build command based on architecture
  if [ "$DO_MULTI_ARCH" = "true" ]; then
    # Multi-architecture build with buildx
    BUILD_ARGS+=(
      "--platform" "$PLATFORMS"
      "--tag" "${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
    )

    # Add push if needed
    if [ "$DO_PUSH" = "true" ]; then
      BUILD_ARGS+=("--push")
    else
      # Attempt to make local image available
      if [[ "$PLATFORMS" == *"linux/amd64"* ]]; then
        BUILD_ARGS+=("--load")
      else
        log "WARN" "Multi-arch images won't be available locally unless pushed"
        BUILD_ARGS+=("--output" "type=image,push=false")
      fi
    fi

    # Execute buildx build
    log "INFO" "Executing multi-arch build with args: ${BUILD_ARGS[*]}"
    docker buildx build "${BUILD_ARGS[@]}" -f "$DOCKERFILE" "$PROJECT_ROOT" | tee -a "$LOG_FILE"
  else
    # Standard build with docker build
    BUILD_ARGS+=(
      "--tag" "${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
      "--file" "$DOCKERFILE"
    )

    # Execute standard build
    log "INFO" "Executing standard build with args: ${BUILD_ARGS[*]}"
    docker build "${BUILD_ARGS[@]}" "$PROJECT_ROOT" | tee -a "$LOG_FILE"

    # Push if needed
    if [ "$DO_PUSH" = "true" ]; then
      log "INFO" "Pushing image to ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
      docker push "${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
    fi
  fi

  # Calculate build duration
  BUILD_END=$(date +%s)
  BUILD_DURATION=$((BUILD_END - BUILD_START))
  log "SUCCESS" "Docker image built in ${BUILD_DURATION} seconds: ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

  # Return build duration for metrics
  echo "$BUILD_DURATION"
}

# Perform security scan
security_scan() {
  if [ "$DO_SCAN" = "true" ]; then
    log "INFO" "Performing security scan on built image..."

    # Check if we built a local image to scan
    if [ "$DO_MULTI_ARCH" = "true" ] && [ "$DO_PUSH" = "false" ] && [[ "$PLATFORMS" != *"linux/amd64"* ]]; then
      log "WARN" "Skipping scan - multi-arch image not available locally"
      return
    fi

    local SCAN_OUTPUT="${BUILD_DIR}/security-scan-${TIMESTAMP}.json"

    # Try to use Trivy if available
    if command -v trivy &> /dev/null; then
      log "INFO" "Scanning with Trivy..."
      trivy image --format json --output "$SCAN_OUTPUT" --exit-code 0 --severity HIGH,CRITICAL "${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}" || true
    else
      # Try with Docker
      log "INFO" "Trivy not found, attempting to use Docker image for scanning..."
      if docker info > /dev/null 2>&1; then
        docker run --rm \
          -v /var/run/docker.sock:/var/run/docker.sock \
          -v "${BUILD_DIR}:/tmp/scan" \
          aquasec/trivy:latest image \
          --format json --output "/tmp/scan/security-scan-${TIMESTAMP}.json" \
          --exit-code 0 --severity HIGH,CRITICAL \
          "${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}" || true
      else
        log "WARN" "Docker not available for scanning. Skipping security scan."
      fi
    fi

    # Check scan results
    if [ -f "$SCAN_OUTPUT" ]; then
      local VULN_COUNT=$(grep -c "VulnerabilityID" "$SCAN_OUTPUT" || echo 0)
      log "INFO" "Security scan completed. Found $VULN_COUNT potential vulnerabilities."

      # Generate human-readable report
      log "INFO" "Full security report available at: $SCAN_OUTPUT"
    else
      log "WARN" "Security scan output not found."
    fi
  else
    log "INFO" "Security scanning skipped"
  fi
}

# Collect and report build metrics
collect_metrics() {
  if [ "$DO_COLLECT_METRICS" = "true" ]; then
    log "INFO" "Collecting build metrics..."

    local METRICS_FILE="${BUILD_DIR}/build-metrics-${TIMESTAMP}.json"
    local BUILD_DURATION="$1"

    # Get image size if available locally
    local IMAGE_SIZE=0
    if docker image inspect "${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}" &> /dev/null; then
      IMAGE_SIZE=$(docker image inspect --format='{{.Size}}' "${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}")
    fi

    # Get layer count if available locally
    local LAYER_COUNT=0
    if docker image inspect "${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}" &> /dev/null; then
      LAYER_COUNT=$(docker image inspect --format='{{len .RootFS.Layers}}' "${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}")
    fi

    # Get system metrics
    local CPU_COUNT=$(nproc 2>/dev/null || echo "unknown")
    local MEM_TOTAL=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "unknown")

    # Write metrics to file
    cat > "$METRICS_FILE" << EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "build": {
    "commit": "${CI_COMMIT}",
    "version": "${VERSION}",
    "environment": "${CI_ENV}",
    "duration_seconds": ${BUILD_DURATION},
    "image_size_bytes": ${IMAGE_SIZE},
    "layer_count": ${LAYER_COUNT},
    "multi_arch": $([ "$DO_MULTI_ARCH" = "true" ] && echo "true" || echo "false"),
    "platforms": "${PLATFORMS}"
  },
  "system": {
    "cpu_count": "${CPU_COUNT}",
    "memory_mb": "${MEM_TOTAL}",
    "docker_version": "$(docker --version | awk '{print $3}' | tr -d ',')"
  }
}
EOF

    log "INFO" "Build metrics saved to $METRICS_FILE"

    # Publish metrics if requested
    if [ "$DO_PUBLISH_ARTIFACTS" = "true" ]; then
      # This would integrate with your metrics collection system
      # For example, sending to Prometheus, DataDog, etc.
      log "INFO" "Publishing metrics to monitoring system"
    fi
  else
    log "INFO" "Metrics collection skipped"
  fi
}

# Publish build artifacts
publish_artifacts() {
  if [ "$DO_PUBLISH_ARTIFACTS" = "true" ]; then
    log "INFO" "Publishing build artifacts..."

    # Create artifacts tarball
    local ARTIFACTS_DIR="${BUILD_DIR}/artifacts-${TIMESTAMP}"
    local ARTIFACTS_TAR="${BUILD_DIR}/artifacts-${TIMESTAMP}.tar.gz"

    mkdir -p "$ARTIFACTS_DIR"

    # Copy important files to artifacts directory
    cp "$LOG_FILE" "$ARTIFACTS_DIR/"
    cp "${BUILD_DIR}/build-info.json" "$ARTIFACTS_DIR/" 2>/dev/null || true
    cp "${BUILD_DIR}/security-scan-${TIMESTAMP}.json" "$ARTIFACTS_DIR/" 2>/dev/null || true
    cp "${BUILD_DIR}/build-metrics-${TIMESTAMP}.json" "$ARTIFACTS_DIR/" 2>/dev/null || true

    # Create metadata file
    cat > "${ARTIFACTS_DIR}/metadata.json" << EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "commit": "${CI_COMMIT}",
  "version": "${VERSION}",
  "image": "${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
}
EOF

    # Create tarball
    tar -czf "$ARTIFACTS_TAR" -C "$(dirname "$ARTIFACTS_DIR")" "$(basename "$ARTIFACTS_DIR")"

    log "SUCCESS" "Build artifacts packaged at $ARTIFACTS_TAR"

    # In a real CI system, you would upload the artifacts to a storage service
    # For example: AWS S3, GCP Storage, Azure Blob, or your CI system's artifact storage
  else
    log "INFO" "Artifact publishing skipped"
  fi
}

# Send notification on failure
notify_failure() {
  log "ERROR" "Build process failed!"

  # Create failure notification payload
  local PAYLOAD="${BUILD_DIR}/failure-notification-${TIMESTAMP}.json"

  cat > "$PAYLOAD" << EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "status": "failure",
  "commit": "${CI_COMMIT}",
  "version": "${VERSION}",
  "environment": "${CI_ENV}",
  "image": "${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}",
  "log_file": "${LOG_FILE}"
}
EOF

  log "INFO" "Failure notification payload created at $PAYLOAD"

  # In a real system, you would implement notification sending here
  # For example: sending to Slack, email, etc.
}

# Main function
main() {
  log "INFO" "======== PhotoPrism2 Docker CI Build ========"
  log "INFO" "CI Environment: $CI_ENV"
  log "INFO" "Commit: $CI_COMMIT"
  log "INFO" "Version: $VERSION"
  log "INFO" "Image: ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

  # Parse command line arguments
  parse_args "$@"

  # Load environment variables
  load_env

  # Check Docker installation
  check_docker

  # Set up registry authentication
  setup_registry_auth

  # Set up build context
  setup_build_context

  # Set up BuildKit for multi-arch
  if [ "$DO_MULTI_ARCH" = "true" ]; then
    setup_buildx
  fi

  # Build Docker image
  BUILD_DURATION=$(build_docker_image)

  # Security scan
  security_scan

  # Collect metrics
  collect_metrics "$BUILD_DURATION"

  # Publish artifacts
  publish_artifacts

  log "SUCCESS" "======== PhotoPrism2 Docker CI Build Completed ========"
  log "INFO" "Build log available at: $LOG_FILE"
}

# Run main function with all args
main "$@"
