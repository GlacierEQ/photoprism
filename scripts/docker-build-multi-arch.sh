#!/bin/bash
# PhotoPrism2 Multi-Architecture Docker Build Script
# Builds Docker images for multiple CPU architectures (amd64, arm64)

set -eo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_LOG="${PROJECT_ROOT}/build/docker-multi-arch-$(date +"%Y%m%d-%H%M%S").log"
DOCKERFILE="${PROJECT_ROOT}/Dockerfile"

# Default build arguments
IMAGE_NAME="${IMAGE_NAME:-photoprism2}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
BUILD_PLATFORMS="${BUILD_PLATFORMS:-linux/amd64,linux/arm64}"
PUSH_IMAGES="${PUSH_IMAGES:-false}"
BUILD_TIMEOUT="${BUILD_TIMEOUT:-7200}"

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
  echo -e "${2:-$NC}[$(date '+%Y-%m-%d %H:%M:%S')] [$1]${NC} ${3:-$1}" | tee -a "$BUILD_LOG"
}

# Show help
show_help() {
  echo "PhotoPrism2 Multi-Architecture Docker Build Script"
  echo ""
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  --name NAME           Image name (default: photoprism2)"
  echo "  --tag TAG             Image tag (default: latest)"
  echo "  --platforms PLATFORMS Comma-separated list of platforms to build for"
  echo "                        (default: linux/amd64,linux/arm64)"
  echo "  --push                Push images to registry"
  echo "  --timeout SECONDS     Build timeout in seconds (default: 7200)"
  echo "  --help                Show this help message"
  echo ""
  echo "Environment variables:"
  echo "  IMAGE_NAME            Same as --name"
  echo "  IMAGE_TAG             Same as --tag"
  echo "  BUILD_PLATFORMS       Same as --platforms"
  echo "  PUSH_IMAGES           Set to 'true' to push images"
  echo "  BUILD_TIMEOUT         Same as --timeout"
  echo ""
  exit 0
}

# Parse command line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --name)
        IMAGE_NAME="$2"
        shift 2
        ;;
      --tag)
        IMAGE_TAG="$2"
        shift 2
        ;;
      --platforms)
        BUILD_PLATFORMS="$2"
        shift 2
        ;;
      --push)
        PUSH_IMAGES="true"
        shift
        ;;
      --timeout)
        BUILD_TIMEOUT="$2"
        shift 2
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

# Check Docker and buildx
check_docker_buildx() {
  log "INFO" "$BLUE" "Checking Docker installation..."

  if ! command -v docker &> /dev/null; then
    log "ERROR" "$RED" "Docker is not installed or not in PATH"
    exit 1
  fi

  log "INFO" "$BLUE" "Docker is installed: $(docker --version)"

  # Check for Docker buildx
  if ! docker buildx version &> /dev/null; then
    log "ERROR" "$RED" "Docker buildx is not available. Please enable Docker BuildKit."
    exit 1
  }

  log "INFO" "$BLUE" "Docker buildx is available: $(docker buildx version | head -1)"
}

# Setup buildx builder
setup_builder() {
  log "INFO" "$BLUE" "Setting up Docker buildx builder..."

  # Check if builder exists
  if ! docker buildx inspect photoprism-builder &> /dev/null; then
    log "INFO" "$BLUE" "Creating new builder instance: photoprism-builder"
    docker buildx create --name photoprism-builder --use
  else
    log "INFO" "$BLUE" "Using existing builder instance: photoprism-builder"
    docker buildx use photoprism-builder
  }

  # Bootstrap builder
  docker buildx inspect --bootstrap
}

# Build multi-architecture image
build_multi_arch() {
  log "INFO" "$BLUE" "Starting multi-architecture build for platforms: $BUILD_PLATFORMS"

  # Setup build arguments
  BUILD_START=$(date +%s)
  VERSION=$(grep -oP 'version:\s*"\K[^"]+' "${PROJECT_ROOT}/package.json" 2>/dev/null || echo "dev")
  BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Prepare build arguments
  BUILD_ARGS=(
    "--platform" "$BUILD_PLATFORMS"
    "--file" "$DOCKERFILE"
    "--build-arg" "BUILD_DATE=${BUILD_DATE}"
    "--build-arg" "VERSION=${VERSION}"
    "--tag" "${IMAGE_NAME}:${IMAGE_TAG}"
    "--label" "org.label-schema.build-date=${BUILD_DATE}"
    "--label" "org.label-schema.version=${VERSION}"
    "--label" "org.label-schema.schema-version=1.0"
    "--progress" "plain"
    "--no-cache"  # For multi-arch it's safer to disable cache
  )

  # Add push if needed
  if [ "$PUSH_IMAGES" = "true" ]; then
    BUILD_ARGS+=("--push")
  else
    BUILD_ARGS+=("--load")
  fi

  # Execute build with buildx
  log "INFO" "$BLUE" "Building multi-architecture image with args: ${BUILD_ARGS[*]}"
  timeout "${BUILD_TIMEOUT}s" docker buildx build "${BUILD_ARGS[@]}" "$PROJECT_ROOT" | tee -a "$BUILD_LOG"

  # Calculate build duration
  BUILD_END=$(date +%s)
  BUILD_DURATION=$((BUILD_END - BUILD_START))
  log "SUCCESS" "$GREEN" "Multi-architecture image built successfully in ${BUILD_DURATION} seconds"
}

# Verify built images
verify_images() {
  log "INFO" "$BLUE" "Verifying built images..."

  # Inspect the image
  docker image inspect "${IMAGE_NAME}:${IMAGE_TAG}" | tee -a "$BUILD_LOG" >/dev/null

  # List image manifests if push was enabled
  if [ "$PUSH_IMAGES" = "true" ]; then
    log "INFO" "$BLUE" "Inspecting pushed image manifests..."
    docker buildx imagetools inspect "${IMAGE_NAME}:${IMAGE_TAG}" | tee -a "$BUILD_LOG"
  fi

  log "SUCCESS" "$GREEN" "Image verification completed"
}

# Main function
main() {
  log "INFO" "$BLUE" "======== PhotoPrism2 Multi-Architecture Docker Build Started ========"

  # Parse command line arguments
  parse_args "$@"

  # Check environment
  check_docker_buildx

  # Setup buildx builder
  setup_builder

  # Build multi-architecture image
  build_multi_arch

  # Verify images
  verify_images

  log "SUCCESS" "$GREEN" "======== PhotoPrism2 Multi-Architecture Docker Build Completed ========"
  log "INFO" "$BLUE" "Build log available at: $BUILD_LOG"

  if [ "$PUSH_IMAGES" = "true" ]; then
    log "INFO" "$BLUE" "Images have been pushed to the registry"
  else
    log "INFO" "$BLUE" "Images are available locally"
  fi
}

# Execute main function with arguments
main "$@"
