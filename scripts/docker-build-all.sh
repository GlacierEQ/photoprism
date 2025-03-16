#!/bin/bash
# PhotoPrism2 Build All Docker Images Script
# Builds Docker images for all environments (dev, staging, prod)

set -eo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"
BUILD_LOG="${PROJECT_ROOT}/build/docker-build-all-$(date +"%Y%m%d-%H%M%S").log"

# Default build arguments
VERSION=$(grep -oP 'version:\s*"\K[^"]+' "${PROJECT_ROOT}/package.json" 2>/dev/null || echo "dev")
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
VCS_REF=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
REGISTRY="${REGISTRY:-docker.io}"
REPOSITORY="${REPOSITORY:-photoprism2}"
PLATFORMS="${PLATFORMS:-linux/amd64}"
PUSH="${PUSH:-false}"

# Create build directory if it doesn't exist
mkdir -p "$(dirname "${BUILD_LOG}")"

# Output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

  echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [${level}]${NC} ${message}" | tee -a "$BUILD_LOG"
}

# Error handling
handle_error() {
  log "ERROR" "Build failed at line $1"
  log "ERROR" "Check the log file at $BUILD_LOG for details"
  exit 1
}

# Set error trap
trap 'handle_error $LINENO' ERR

# Function to show help
show_help() {
  echo "PhotoPrism2 Build All Docker Images"
  echo ""
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  --registry REGISTRY  Docker registry (default: docker.io)"
  echo "  --repository REPO    Repository name (default: photoprism2)"
  echo "  --platforms PLAT     Comma-separated platforms (default: linux/amd64)"
  echo "  --push               Push images to registry"
  echo "  --skip-dev           Skip development image"
  echo "  --skip-staging       Skip staging image"
  echo "  --skip-prod          Skip production image"
  echo "  --help               Show this help message"
  echo ""
  exit 0
}

# Parse command line arguments
parse_args() {
  local SKIP_DEV=false
  local SKIP_STAGING=false
  local SKIP_PROD=false

  while [[ $# -gt 0 ]]; do
    case $1 in
      --registry)
        REGISTRY="$2"
        shift 2
        ;;
      --repository)
        REPOSITORY="$2"
        shift 2
        ;;
      --platforms)
        PLATFORMS="$2"
        shift 2
        ;;
      --push)
        PUSH="true"
        shift
        ;;
      --skip-dev)
        SKIP_DEV=true
        shift
        ;;
      --skip-staging)
        SKIP_STAGING=true
        shift
        ;;
      --skip-prod)
        SKIP_PROD=true
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

  # Return values
  echo "$SKIP_DEV $SKIP_STAGING $SKIP_PROD"
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

  # Check for BuildKit
  if [ "${DOCKER_BUILDKIT:-0}" != "1" ]; then
    log "WARN" "DOCKER_BUILDKIT is not enabled, consider enabling for better performance"
    export DOCKER_BUILDKIT=1
  fi
}

# Build development image
build_dev_image() {
  log "INFO" "Building development image..."

  local DEV_TAG="${REGISTRY}/${REPOSITORY}:dev"
  local BUILD_ARGS=(
    "--build-arg" "NODE_VERSION=${NODE_VERSION:-16}"
    "--build-arg" "GO_VERSION=${GO_VERSION:-1.19}"
    "--build-arg" "ALPINE_VERSION=${ALPINE_VERSION:-3.17}"
    "--build-arg" "BUILD_DATE=${BUILD_DATE}"
    "--build-arg" "VERSION=${VERSION}"
    "--build-arg" "VCS_REF=${VCS_REF}"
  )

  # Build the image
  log "INFO" "Building development image: ${DEV_TAG}"
  docker build "${BUILD_ARGS[@]}" \
    -t "${DEV_TAG}" \
    -f "${PROJECT_ROOT}/docker/config/Dockerfile.dev" \
    "${PROJECT_ROOT}" | tee -a "$BUILD_LOG"

  # Push if requested
  if [ "$PUSH" = "true" ]; then
    log "INFO" "Pushing development image: ${DEV_TAG}"
    docker push "${DEV_TAG}" | tee -a "$BUILD_LOG"
  fi

  log "SUCCESS" "Development image build completed"
}

# Build staging image
build_staging_image() {
  log "INFO" "Building staging image..."

  local STAGING_TAG="${REGISTRY}/${REPOSITORY}:staging"
  local BUILD_ARGS=(
    "--build-arg" "NODE_VERSION=${NODE_VERSION:-16}"
    "--build-arg" "GO_VERSION=${GO_VERSION:-1.19}"
    "--build-arg" "ALPINE_VERSION=${ALPINE_VERSION:-3.17}"
    "--build-arg" "BUILD_DATE=${BUILD_DATE}"
    "--build-arg" "VERSION=${VERSION}"
    "--build-arg" "VCS_REF=${VCS_REF}"
  )

  # Build the image
  log "INFO" "Building staging image: ${STAGING_TAG}"
  docker build "${BUILD_ARGS[@]}" \
    -t "${STAGING_TAG}" \
    -f "${PROJECT_ROOT}/Dockerfile" \
    "${PROJECT_ROOT}" | tee -a "$BUILD_LOG"

  # Push if requested
  if [ "$PUSH" = "true" ]; then
    log "INFO" "Pushing staging image: ${STAGING_TAG}"
    docker push "${STAGING_TAG}" | tee -a "$BUILD_LOG"
  fi

  log "SUCCESS" "Staging image build completed"
}

# Build production image
build_prod_image() {
  log "INFO" "Building production image..."

  local PROD_TAG="${REGISTRY}/${REPOSITORY}:latest"
  local VERSION_TAG="${REGISTRY}/${REPOSITORY}:${VERSION}"
  local BUILD_ARGS=(
    "--build-arg" "NODE_VERSION=${NODE_VERSION:-16}"
    "--build-arg" "GO_VERSION=${GO_VERSION:-1.19}"
    "--build-arg" "ALPINE_VERSION=${ALPINE_VERSION:-3.17}"
    "--build-arg" "BUILD_DATE=${BUILD_DATE}"
    "--build-arg" "VERSION=${VERSION}"
    "--build-arg" "VCS_REF=${VCS_REF}"
  )

  # Build the image
  log "INFO" "Building production image: ${PROD_TAG}"
  docker build "${BUILD_ARGS[@]}" \
    -t "${PROD_TAG}" \
    -t "${VERSION_TAG}" \
    -f "${PROJECT_ROOT}/docker/config/Dockerfile.prod" \
    "${PROJECT_ROOT}" | tee -a "$BUILD_LOG"

  # Push if requested
  if [ "$PUSH" = "true" ]; then
    log "INFO" "Pushing production image: ${PROD_TAG}"
    docker push "${PROD_TAG}" | tee -a "$BUILD_LOG"

    log "INFO" "Pushing versioned image: ${VERSION_TAG}"
    docker push "${VERSION_TAG}" | tee -a "$BUILD_LOG"
  fi

  log "SUCCESS" "Production image build completed"
}

# Run security scans
run_security_scans() {
  log "INFO" "Running security scans on images..."

  if command -v trivy &> /dev/null; then
    local IMAGES=(
      "${REGISTRY}/${REPOSITORY}:dev"
      "${REGISTRY}/${REPOSITORY}:staging"
      "${REGISTRY}/${REPOSITORY}:latest"
    )

    for IMAGE in "${IMAGES[@]}"; do
      if docker image inspect "$IMAGE" &>/dev/null; then
        log "INFO" "Scanning image: ${IMAGE}"
        trivy image --exit-code 0 --severity HIGH,CRITICAL "${IMAGE}" | tee -a "$BUILD_LOG"
      fi
    done
  else
    log "WARN" "Trivy not installed, skipping security scans"
  fi
}

# Report image sizes
report_sizes() {
  log "INFO" "Reporting image sizes..."

  printf "%-20s %-15s\n" "IMAGE" "SIZE" | tee -a "$BUILD_LOG"
  printf "%-20s %-15s\n" "-----" "----" | tee -a "$BUILD_LOG"

  local IMAGES=(
    "${REGISTRY}/${REPOSITORY}:dev"
    "${REGISTRY}/${REPOSITORY}:staging"
    "${REGISTRY}/${REPOSITORY}:latest"
  )

  for IMAGE in "${IMAGES[@]}"; do
    if docker image inspect "$IMAGE" &>/dev/null; then
      local SIZE=$(docker image inspect --format='{{.Size}}' "$IMAGE")
      local SIZE_MB=$(echo "scale=2; $SIZE/1024/1024" | bc)
      printf "%-20s %-15s\n" "$IMAGE" "${SIZE_MB}MB" | tee -a "$BUILD_LOG"
    else
      printf "%-20s %-15s\n" "$IMAGE" "Not built" | tee -a "$BUILD_LOG"
    fi
  done
}

# Main function
main() {
  log "INFO" "======== PhotoPrism2 Build All Docker Images ========"
  log "INFO" "Registry: $REGISTRY"
  log "INFO" "Repository: $REPOSITORY"
  log "INFO" "Platforms: $PLATFORMS"
  log "INFO" "Version: $VERSION"

  # Parse command line arguments
  read -r SKIP_DEV SKIP_STAGING SKIP_PROD <<< "$(parse_args "$@")"

  # Load environment variables
  load_env

  # Check for Docker
  check_docker

  # Build images
  if [ "$SKIP_DEV" != "true" ]; then
    build_dev_image
  else
    log "INFO" "Skipping development image build"
  fi

  if [ "$SKIP_STAGING" != "true" ]; then
    build_staging_image
  else
    log "INFO" "Skipping staging image build"
  fi

  if [ "$SKIP_PROD" != "true" ]; then
    build_prod_image
  else
    log "INFO" "Skipping production image build"
  fi

  # Run security scans
  run_security_scans

  # Report image sizes
  report_sizes

  log "SUCCESS" "======== All Docker Images Build Completed ========"
  log "INFO" "Build log available at: $BUILD_LOG"
}

# Run main function with all args
main "$@"
