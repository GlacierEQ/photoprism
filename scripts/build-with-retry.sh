#!/bin/bash

# Set error handling
set -o pipefail

# Load environment variables
ENV_FILE=".env.docker"
if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
else
  echo "Warning: $ENV_FILE not found, using default values"
fi

# Setup logging
LOG_DIR="./logs"
LOG_FILE="${LOG_DIR}/docker-build-$(date +%Y%m%d-%H%M%S).log"
mkdir -p ${LOG_DIR}

# Default variables if not set in environment
: "${DOCKER_IMAGE_NAME:=photoprism2}"
: "${DOCKER_IMAGE_TAG:=latest}"
: "${DOCKER_BUILD_ATTEMPTS:=3}"
: "${DOCKER_BUILD_DELAY:=5}"
: "${DOCKER_BUILD_TIMEOUT:=300}"
: "${DOCKER_BUILD_ARGS:=--no-cache --force-rm}"
: "${LOG_LEVEL:=INFO}"

# Initialize benchmark data
start_time_total=$(date +%s.%N)
build_success=false

# Logging function with levels
log() {
  local level=$1
  local message=$2
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

  # Only output if log level matches minimum level
  if [[ "$level" == "ERROR" ]] || [[ "$level" == "WARNING" ]] || [[ "$LOG_LEVEL" == "DEBUG" ]] || [[ "$LOG_LEVEL" == "INFO" && "$level" != "DEBUG" ]]; then
    echo -e "[$timestamp] [$level] $message"
  fi

  # Always write to log file
  echo -e "[$timestamp] [$level] $message" >> ${LOG_FILE}
}

log "INFO" "Docker build script started"
log "DEBUG" "Environment variables loaded from $ENV_FILE"

# Check system resources
check_system_resources() {
  log "INFO" "Checking system resources..."

  # Check disk space
  disk_space=$(df -h . | awk 'NR==2 {print $4}')
  log "INFO" "Available disk space: $disk_space"

  # Check memory
  if command -v free >/dev/null 2>&1; then
    memory=$(free -h | awk '/^Mem:/ {print $4}')
    log "INFO" "Available memory: $memory"
  fi

  # Check CPU load
  if command -v uptime >/dev/null 2>&1; then
    load=$(uptime | awk -F'[a-z]:' '{ print $2}')
    log "INFO" "Current system load: $load"
  fi

  # Check Docker system info
  docker system df >> ${LOG_FILE} 2>&1 || log "WARNING" "Failed to get Docker disk usage"
}

# Function to clean up Docker environment
clean_docker_environment() {
  log "INFO" "Cleaning Docker environment..."

  # Remove dangling images if disk space is low
  if docker system df | grep "Images" | awk '{print $5}' | grep -q "^[8-9][0-9]\.[0-9]%" || docker system df | grep "Images" | awk '{print $5}' | grep -q "^100"; then
    log "WARNING" "Docker images using high disk space, cleaning dangling images"
    docker image prune --force >> ${LOG_FILE} 2>&1
  fi

  # Ensure Docker daemon is running
  docker info > /dev/null 2>&1 || {
    log "ERROR" "Docker daemon not running"
    return 1
  }

  return 0
}

# Function to prepare build context
prepare_build_context() {
  log "INFO" "Preparing build context..."

  # Create temporary .dockerignore if it doesn't exist
  if [ ! -f .dockerignore ]; then
    log "INFO" "Creating .dockerignore file"
    cat > .dockerignore << EOF
.git
logs/
.env*
node_modules/
**/node_modules/
**/.DS_Store
EOF
  fi

  # Check Dockerfile existence
  if [ ! -f Dockerfile ]; then
    log "ERROR" "Dockerfile not found in current directory"
    return 1
  fi

  return 0
}

# Function to attempt Docker build with retries and performance tracking
build_with_retry() {
  local max_attempts=${DOCKER_BUILD_ATTEMPTS}
  local attempt=1
  local delay=${DOCKER_BUILD_DELAY}
  local build_args=${DOCKER_BUILD_ARGS}
  local image_name="${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}"

  while [ $attempt -le $max_attempts ]
  do
    log "INFO" "Build attempt $attempt of $max_attempts..."

    # Pre-pull base images for caching
    log "INFO" "Pre-pulling base images to optimize build..."
    local start_time_pull=$(date +%s.%N)

    # Extract base images from Dockerfile
    base_images=$(grep -E '^FROM' Dockerfile | awk '{print $2}')
    if [ -z "$base_images" ]; then
      base_images="golang:1.19-alpine alpine:3.17 node:16-alpine"
      log "WARNING" "No FROM instructions found in Dockerfile, using default images"
    fi

    # Pull each base image with a timeout
    for image in $base_images; do
      log "INFO" "Pulling $image..."
      timeout ${DOCKER_PULL_TIMEOUT:-60} docker pull $image >> ${LOG_FILE} 2>&1 || log "WARNING" "Failed to pull $image"
    done

    local end_time_pull=$(date +%s.%N)
    local pull_duration=$(echo "$end_time_pull - $start_time_pull" | bc)
    log "INFO" "Image pulling completed in $pull_duration seconds"

    # Build with timeout and performance tracking
    log "INFO" "Starting Docker build..."
    local start_time_build=$(date +%s.%N)

    # Set build-args from environment if provided
    build_args_env=""
    env | grep '^BUILD_ARG_' | while read -r line; do
      arg_name=$(echo "$line" | cut -d'=' -f1 | sed 's/^BUILD_ARG_//')
      arg_value=$(echo "$line" | cut -d'=' -f2-)
      build_args_env="$build_args_env --build-arg $arg_name=$arg_value"
    done

    # Combine fixed and environment build args
    full_build_args="$build_args $build_args_env"

    # Create full build command
    build_cmd="docker build $full_build_args -t $image_name ."
    log "DEBUG" "Build command: $build_cmd"

    # Execute build with timeout
    if timeout ${DOCKER_BUILD_TIMEOUT} bash -c "$build_cmd" >> ${LOG_FILE} 2>&1; then
      local end_time_build=$(date +%s.%N)
      local build_duration=$(echo "$end_time_build - $start_time_build" | bc)

      log "INFO" "Build successful! Completed in $build_duration seconds"

      # Validate the built image
      if docker image inspect $image_name > /dev/null 2>&1; then
        log "INFO" "Image validation successful"
        image_size=$(docker image inspect $image_name --format='{{.Size}}' | numfmt --to=iec-i)
        log "INFO" "Image size: $image_size"
        build_success=true
        return 0
      else
        log "ERROR" "Built image not found or invalid"
      fi
    else
      local end_time_build=$(date +%s.%N)
      local build_duration=$(echo "$end_time_build - $start_time_build" | bc)

      log "ERROR" "Build failed after $build_duration seconds"

      # Check build logs for common errors
      if grep -q "no space left on device" ${LOG_FILE}; then
        log "ERROR" "Build failed due to insufficient disk space"
        docker system prune -f >> ${LOG_FILE} 2>&1
      elif grep -q "network timeout" ${LOG_FILE}; then
        log "ERROR" "Build failed due to network timeout"
      fi

      log "INFO" "Waiting $delay seconds before retry..."
      sleep $delay
      delay=$((delay * 2))
      attempt=$((attempt + 1))
    fi
  done

  log "ERROR" "All build attempts failed after $max_attempts tries."
  return 1
}

# Check internet connectivity
check_internet_connectivity() {
  log "INFO" "Checking internet connectivity..."
  if curl -s --connect-timeout 5 https://www.google.com > /dev/null; then
    log "INFO" "Internet connection is working"
  else
    log "ERROR" "No internet connectivity detected. Please check your network connection."
    return 1
  fi
  return 0
}

# Check Docker version
check_docker_version() {
  log "INFO" "Checking Docker version..."
  if docker --version &> /dev/null; then
    docker_version=$(docker --version | awk '{print $3}' | sed 's/,//')
    log "INFO" "Docker version: $docker_version"
  else
    log "ERROR" "Docker is not installed or not in PATH."
    return 1
  fi
  return 0
}

# Main execution flow
main() {
  log "INFO" "Starting Docker build workflow..."

  # Check Docker version
  if ! check_docker_version; then
    exit 1
  fi

  # Check internet connectivity
  if ! check_internet_connectivity; then
    exit 1
  fi

  # Run network diagnostics
  log "INFO" "Checking Docker connectivity..."
  bash ./scripts/docker-network-check.sh | tee -a ${LOG_FILE}

  # Ensure Docker authentication
  log "INFO" "Ensuring Docker Hub authentication..."
  bash ./scripts/docker-login-helper.sh | tee -a ${LOG_FILE}

  # Check system resources
  check_system_resources

  # Clean Docker environment
  clean_docker_environment || {
    log "ERROR" "Failed to prepare Docker environment"
    return 1
  }

  # Prepare build context
  prepare_build_context || {
    log "ERROR" "Failed to prepare build context"
    return 1
  }

  # Execute build with retry logic
  log "INFO" "Starting build process with retry logic..."
  build_with_retry

  # Check if docker-compose is available, if not use docker compose
  if command -v docker-compose &> /dev/null; then
    compose_cmd="docker-compose"
  else
    compose_cmd="docker compose"
  fi

  # Start the services
  log "INFO" "Starting services with $compose_cmd..."
  $compose_cmd up -d
  build_result=$?

  # Finish benchmarking
  end_time_total=$(date +%s.%N)
  total_duration=$(echo "$end_time_total - $start_time_total" | bc)

  if [ $build_result -eq 0 ] && [ "$build_success" = true ]; then
    log "INFO" "Build workflow completed successfully in $total_duration seconds"
    echo "====================================================="
    echo "✅ Docker build successful!"
    echo "Image: ${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}"
    echo "Total time: $total_duration seconds"
    echo "Log file: $LOG_FILE"
    echo "====================================================="
    return 0
  else
    log "ERROR" "Build workflow failed after $total_duration seconds"
    echo "====================================================="
    echo "❌ Docker build failed!"
    echo "Check log file for details: $LOG_FILE"
    echo "====================================================="
    return 1
  fi
}

# Execute main function
main
exit $?
