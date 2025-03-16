#!/bin/bash
# PhotoPrism2 Docker Build Script
# Builds Docker images with proper caching, optimization and security checks

set -eo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"
BUILD_LOG="${PROJECT_ROOT}/build/docker-build-$(date +"%Y%m%d-%H%M%S").log"
DOCKERFILE="${PROJECT_ROOT}/Dockerfile"
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.yml"

# Default build arguments
BUILD_ENV="${BUILD_ENV:-production}"
CACHE_FROM="${CACHE_FROM:-}"
BUILD_TIMEOUT="${BUILD_TIMEOUT:-3600}"
PULL_DEPS="${PULL_DEPS:-true}"
PUSH_IMAGES="${PUSH_IMAGES:-false}"
DO_PRUNE="${DO_PRUNE:-false}"
SECURITY_SCAN="${SECURITY_SCAN:-true}"
VERSION=$(grep -oP 'version:\s*"\K[^"]+' "${PROJECT_ROOT}/package.json" 2>/dev/null || echo "dev")
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
IMAGE_TAG="${IMAGE_TAG:-latest}"

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
  echo "PhotoPrism2 Docker Build Script"
  echo ""
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  --env ENV            Build environment (default: production)"
  echo "  --tag TAG            Image tag (default: latest)"
  echo "  --cache-from IMAGE   Use specified image for cache"
  echo "  --no-cache           Disable Docker build cache"
  echo "  --pull               Pull base images before building"
  echo "  --push               Push images after building"
  echo "  --prune              Prune Docker images after building"
  echo "  --no-security-scan   Skip security scanning"
  echo "  --timeout SECONDS    Build timeout in seconds (default: 3600)"
  echo "  --help               Show this help message"
  echo ""
  echo "Environment variables:"
  echo "  BUILD_ENV            Same as --env"
  echo "  IMAGE_TAG            Same as --tag"
  echo "  CACHE_FROM           Same as --cache-from"
  echo "  PULL_DEPS            Set to 'false' to disable pulling dependencies"
  echo "  PUSH_IMAGES          Set to 'true' to push images"
  echo "  DO_PRUNE             Set to 'true' to prune images"
  echo "  SECURITY_SCAN        Set to 'false' to skip security scanning"
  echo "  BUILD_TIMEOUT        Same as --timeout"
  echo ""
  exit 0
}

# Parse command line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --env)
        BUILD_ENV="$2"
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
      --no-cache)
        CACHE_FROM="--no-cache"
        shift
        ;;
      --pull)
        PULL_DEPS="true"
        shift
        ;;
      --push)
        PUSH_IMAGES="true"
        shift
        ;;
      --prune)
        DO_PRUNE="true"
        shift
        ;;
      --no-security-scan)
        SECURITY_SCAN="false"
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

  if ! docker info &> /dev/null; then
    log "ERROR" "Docker daemon is not running or current user doesn't have permission"
    exit 1
  }

  if command -v docker compose &> /dev/null; then
    log "INFO" "Docker Compose V2 is installed"
    DOCKER_COMPOSE="docker compose"
  elif command -v docker-compose &> /dev/null; then
    log "INFO" "Docker Compose V1 is installed: $(docker-compose --version)"
    DOCKER_COMPOSE="docker-compose"
  else
    log "WARN" "Docker Compose is not installed. Building with docker only."
    DOCKER_COMPOSE=""
  fi
}

# Prepare build environment
prepare_environment() {
  log "INFO" "Preparing build environment..."

  # Create temporary build directory
  TEMP_BUILD_DIR="$(mktemp -d)"
  log "INFO" "Created temporary build directory: $TEMP_BUILD_DIR"

  # Generate build info file
  BUILD_INFO_FILE="${TEMP_BUILD_DIR}/build-info.json"
  cat > "$BUILD_INFO_FILE" << EOF
{
  "version": "${VERSION}",
  "buildDate": "${BUILD_DATE}",
  "environment": "${BUILD_ENV}",
  "buildHost": "$(hostname)",
  "dockerVersion": "$(docker --version | awk '{print $3}' | tr -d ',')"
}
EOF
  log "INFO" "Generated build info at $BUILD_INFO_FILE"

  # Ensure Docker network exists
  if ! docker network inspect photoprism_network &> /dev/null; then
    log "INFO" "Creating Docker network: photoprism_network"
    docker network create photoprism_network
  else
    log "INFO" "Docker network photoprism_network already exists"
  fi
}

# Pull base images for build caching
pull_base_images() {
  if [ "$PULL_DEPS" = "true" ]; then
    log "INFO" "Pulling base images for better caching..."

    # Extract base images from Dockerfile
    BASE_IMAGES=$(grep -E '^FROM' "$DOCKERFILE" | awk '{print $2}' | cut -d ":" -f1 | sort -u)

    for image in $BASE_IMAGES; do
      log "INFO" "Pulling base image: $image"
      docker pull "$image" || log "WARN" "Failed to pull $image, continuing with build"
    done
  else
    log "INFO" "Skipping base image pulls"
  fi
}

# Build Docker image using the Dockerfile
build_docker_image() {
  log "INFO" "Building Docker image with tag: photoprism2:${IMAGE_TAG}"

  # Calculate build start time
  BUILD_START=$(date +%s)

  # Prepare build arguments
  BUILD_ARGS=(
    "--tag" "photoprism2:${IMAGE_TAG}"
    "--file" "$DOCKERFILE"
    "--build-arg" "BUILD_DATE=${BUILD_DATE}"
    "--build-arg" "VERSION=${VERSION}"
    "--build-arg" "NODE_ENV=${BUILD_ENV}"
    "--label" "org.label-schema.build-date=${BUILD_DATE}"
    "--label" "org.label-schema.version=${VERSION}"
    "--label" "org.label-schema.schema-version=1.0"
    "--label" "maintainer=PhotoPrism2 Team <team@photoprism2.org>"
  )

  # Add cache-from if specified
  if [ -n "$CACHE_FROM" ]; then
    if [ "$CACHE_FROM" = "--no-cache" ]; then
      BUILD_ARGS+=("--no-cache")
    else
      BUILD_ARGS+=("--cache-from" "$CACHE_FROM")
    fi
  fi

  # Add build timeout
  if [ -n "$BUILD_TIMEOUT" ]; then
    BUILD_ARGS+=("--timeout" "${BUILD_TIMEOUT}s")
  fi

  # Execute build with timeout
  log "INFO" "Starting Docker build with args: ${BUILD_ARGS[*]}"
  docker build "${BUILD_ARGS[@]}" "$PROJECT_ROOT" | tee -a "$BUILD_LOG"

  # Calculate build duration
  BUILD_END=$(date +%s)
  BUILD_DURATION=$((BUILD_END - BUILD_START))
  log "SUCCESS" "Docker image built successfully in ${BUILD_DURATION} seconds"
}

# Scan image for security vulnerabilities
security_scan() {
  if [ "$SECURITY_SCAN" = "true" ]; then
    log "INFO" "Performing security scan on built image..."

    if command -v trivy &> /dev/null; then
      log "INFO" "Using Trivy for security scanning"
      trivy image --exit-code 0 --severity HIGH,CRITICAL --no-progress "photoprism2:${IMAGE_TAG}" | tee -a "${BUILD_LOG}" || true
    else
      log "WARN" "Trivy not installed. Attempting to use Docker image..."
      docker run --rm \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v "${TEMP_BUILD_DIR}:/tmp/scan" \
        aquasec/trivy:latest image --exit-code 0 --severity HIGH,CRITICAL --no-progress "photoprism2:${IMAGE_TAG}" | tee -a "${BUILD_LOG}" || true
    fi

    log "INFO" "Security scan completed"
  else
    log "INFO" "Security scan skipped"
  fi
}

# Build images with docker-compose
build_with_compose() {
  if [ -n "$DOCKER_COMPOSE" ] && [ -f "$COMPOSE_FILE" ]; then
    log "INFO" "Building Docker images using docker-compose..."

    COMPOSE_ARGS=("-f" "$COMPOSE_FILE" "build")

    # Add build arguments
    if [ "$PULL_DEPS" = "true" ]; then
      COMPOSE_ARGS+=("--pull")
    fi

    if [ -n "$CACHE_FROM" ] && [ "$CACHE_FROM" = "--no-cache" ]; then
      COMPOSE_ARGS+=("--no-cache")
    fi

    # Execute docker-compose build
    $DOCKER_COMPOSE "${COMPOSE_ARGS[@]}" | tee -a "$BUILD_LOG"
    log "SUCCESS" "Docker Compose build completed successfully"
  else
    log "INFO" "Skipping docker-compose build"
  fi
}

# Push images to registry if needed
push_images() {
  if [ "$PUSH_IMAGES" = "true" ]; then
    log "INFO" "Pushing images to registry..."

    # Check for registry credentials
    if [ -z "${DOCKER_REGISTRY_URL:-}" ]; then
      log "WARN" "DOCKER_REGISTRY_URL not set, using default Docker Hub"
    fi

    # Tag the image for the registry
    REGISTRY_URL="${DOCKER_REGISTRY_URL:-docker.io}"
    REGISTRY_REPO="${DOCKER_REGISTRY_REPO:-photoprism2}"
    REGISTRY_TAG="${REGISTRY_URL}/${REGISTRY_REPO}:${IMAGE_TAG}"

    log "INFO" "Tagging image as ${REGISTRY_TAG}"
    docker tag "photoprism2:${IMAGE_TAG}" "${REGISTRY_TAG}"

    # Login to registry if credentials provided
    if [ -n "${DOCKER_REGISTRY_USER:-}" ] && [ -n "${DOCKER_REGISTRY_PASSWORD:-}" ]; then
      log "INFO" "Logging in to registry ${REGISTRY_URL}"
      echo "${DOCKER_REGISTRY_PASSWORD}" | docker login "${REGISTRY_URL}" -u "${DOCKER_REGISTRY_USER}" --password-stdin
    fi

    # Push the image
    log "INFO" "Pushing image to ${REGISTRY_TAG}"
    docker push "${REGISTRY_TAG}"
    log "SUCCESS" "Image pushed successfully"
  else
    log "INFO" "Image push skipped"
  fi
}

# Clean up after build
cleanup() {
  log "INFO" "Cleaning up build environment..."

  # Remove temporary directory
  if [ -d "$TEMP_BUILD_DIR" ]; then
    rm -rf "$TEMP_BUILD_DIR"
    log "INFO" "Removed temporary build directory"
  fi

  # Prune Docker images if requested
  if [ "$DO_PRUNE" = "true" ]; then
    log "INFO" "Pruning unused Docker images..."
    docker image prune -f
    log "INFO" "Docker image pruning complete"
  fi

  log "INFO" "Cleanup complete"
}

# Main function
main() {
  log "INFO" "======== PhotoPrism2 Docker Build Started ========"
  log "INFO" "Build environment: $BUILD_ENV"
  log "INFO" "Image tag: $IMAGE_TAG"
  log "INFO" "Version: $VERSION"

  # Parse command line arguments
  parse_args "$@"

  # Load environment variables
  load_env

  # Check for Docker
  check_docker

  # Prepare build environment
  prepare_environment

  # Pull base images
  pull_base_images

  # Build Docker image
  build_docker_image

  # Scan image for security vulnerabilities
  security_scan

  # Build with docker-compose
  build_with_compose

  # Push images if needed
  push_images

  # Clean up
  cleanup

  log "SUCCESS" "======== PhotoPrism2 Docker Build Completed ========"
  log "INFO" "Build log available at: $BUILD_LOG"
}

# Run main function with all args
main "$@"
