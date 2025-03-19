#!/bin/bash

# Fix relative paths to work from any directory
# Load environment variables
if [ -f "$(dirname "$(dirname "$0")")/.env.docker" ]; then
  source "$(dirname "$(dirname "$0")")/.env.docker"
fi

# Setup logging
LOG_DIR="$(dirname "$(dirname "$0")")/logs"
LOG_FILE="${LOG_DIR}/docker-login-$(date +%Y%m%d-%H%M%S).log"
mkdir -p ${LOG_DIR}

log() {
  local level=$1
  local message=$2
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  echo -e "[$timestamp] [$level] $message"
  echo -e "[$timestamp] [$level] $message" >> ${LOG_FILE}
}

log "INFO" "Docker authentication helper started"

# Function to securely handle login
docker_login() {
  local registry=${1:-"docker.io"}
  local username="$2"
  local password="$3"
  local registry_var=$(echo "$registry" | tr '.-' '_' | tr '[:lower:]' '[:upper:]')

  # Check if we should use credentials from environment
  if [ -z "$username" ] || [ -z "$password" ]; then
    # Try to get from environment based on registry
    eval username_var="\$${registry_var}_USERNAME"
    eval password_var="\$${registry_var}_PASSWORD"

    if [ -n "$username_var" ] && [ -n "$password_var" ]; then
      username="$username_var"
      password="$password_var"
      log "INFO" "Using credentials from environment variables for $registry"
    else
      # For docker.io, fall back to DOCKER_USERNAME
      if [ "$registry" = "docker.io" ] && [ -n "$DOCKER_USERNAME" ] && [ -n "$DOCKER_PASSWORD" ]; then
        username="$DOCKER_USERNAME"
        password="$DOCKER_PASSWORD"
        log "INFO" "Using Docker Hub credentials from environment variables"
      else
        log "INFO" "No credentials found for $registry"
        log "INFO" "Please enter credentials for $registry:"
        read -p "Username for $registry: " username
        read -s -p "Password for $registry: " password
        echo ""
      fi
    fi
  fi

  # Validate credentials are not empty
  if [ -z "$username" ] || [ -z "$password" ]; then
    log "ERROR" "Empty credentials provided for $registry"
    return 1
  fi

  # Attempt login
  log "INFO" "Attempting login to $registry..."
  if [ "$registry" = "docker.io" ]; then
    # For Docker Hub
    if echo "$password" | docker login -u "$username" --password-stdin > /dev/null 2>&1; then
      log "INFO" "Successfully logged in to $registry"
      return 0
    else
      log "ERROR" "Failed to login to $registry"
      docker login -u "$username" --password-stdin <<<$password 2>&1 | tee -a ${LOG_FILE} # Capture detailed login error
      return 1
    fi
  else
    # For other registries
    if echo "$password" | docker login -u "$username" --password-stdin "$registry" > /dev/null 2>&1; then
      log "INFO" "Successfully logged in to $registry"
      return 0
    else
      log "ERROR" "Failed to login to $registry"
      return 1
    fi
  fi
}

# Main login process
if [ "$USE_DOCKER_AUTH" = "false" ]; then
  log "INFO" "Docker authentication skipped due to configuration"
else
  # Try Docker Hub first
  docker_login "docker.io"

  # Check if we need to authenticate with additional registries
  if [ -n "$ADDITIONAL_REGISTRIES" ]; then
    log "INFO" "Processing additional registries: $ADDITIONAL_REGISTRIES"
    for registry in $(echo $ADDITIONAL_REGISTRIES | tr ',' ' '); do
      docker_login "$registry"
    done
  fi
fi

# Verify credentials worked by attempting to pull images
log "INFO" "Verifying registry access by pulling base images..."

pull_with_timeout() {
  local image="$1"
  local timeout=${2:-60}

  log "INFO" "Pulling $image (timeout: ${timeout}s)..."

  # Using timeout command if available
  if command -v timeout >/dev/null 2>&1; then
    if timeout "$timeout" docker pull "$image" > /dev/null 2>&1; then
      log "INFO" "Successfully pulled $image"
      return 0
    else
      log "WARNING" "Failed to pull $image within ${timeout}s"
      return 1
    fi
  else
    # Fallback if timeout command is not available
    if docker pull "$image" > /dev/null 2>&1; then
      log "INFO" "Successfully pulled $image"
      return 0
    else
      log "WARNING" "Failed to pull $image"
      return 1
    fi
  fi
}

# Try to pull required base images with a timeout
pull_with_timeout "golang:1.19-alpine" 30
pull_with_timeout "alpine:3.17" 20
pull_with_timeout "node:16-alpine" 30

log "INFO" "Docker authentication process completed"
echo "Full login log: ${LOG_FILE}"
