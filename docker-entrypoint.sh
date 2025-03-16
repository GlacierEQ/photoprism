#!/bin/bash
set -e

# Configure bash strict mode
set -o errexit
set -o pipefail
set -o nounset

# Setup logging
log() {
  local level="$1"
  local message="$2"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message"
}

log_info() {
  log "INFO" "$1"
}

log_warn() {
  log "WARN" "$1"
}

log_error() {
  log "ERROR" "$1"
}

# Load environment variables from .env file if exists
if [ -f ".env" ]; then
  log_info "Loading environment variables from .env file"
  set -a
  source .env
  set +a
fi

# Validate required environment variables
validate_env_vars() {
  local missing_vars=()

  # Check for required environment variables
  if [ -z "${DATABASE_URL:-}" ]; then
    missing_vars+=("DATABASE_URL")
  fi

  if [ -z "${STORAGE_PATH:-}" ]; then
    missing_vars+=("STORAGE_PATH")
  fi

  # Report any missing variables
  if [ ${#missing_vars[@]} -ne 0 ]; then
    log_error "Missing required environment variables: ${missing_vars[*]}"
    exit 1
  fi

  log_info "Environment validation passed"
}

# Function to handle cleanup on exit
cleanup() {
  log_info "Received signal, shutting down gracefully..."

  # Perform any necessary cleanup
  log_info "Saving application state..."

  # You can add additional cleanup steps here

  log_info "Cleanup completed. Exiting."
  exit 0
}

# Register trap for SIGTERM and SIGINT
trap cleanup SIGTERM SIGINT

# Validate environment variables
validate_env_vars

# Database connection check with timeout
check_db_connection() {
  local db_host="postgres"
  local db_port="5432"
  local max_retries=30
  local retry_interval=2
  local counter=0

  log_info "Checking database connection to ${db_host}:${db_port}..."

  while ! nc -z "${db_host}" "${db_port}"; do
    counter=$((counter+1))
    if [ $counter -eq $max_retries ]; then
      log_error "Failed to connect to database after $max_retries attempts. Exiting."
      exit 1
    fi
    log_info "Waiting for database connection... ($counter/$max_retries)"
    sleep $retry_interval
  done

  log_info "Database connection established."

  # Additional wait for database to be fully ready
  sleep 2
}

# Check database connection
check_db_connection

# Create storage directories with proper permissions
create_storage_dirs() {
  log_info "Setting up storage directories..."

  if [ ! -d "${STORAGE_PATH}/photos" ]; then
    mkdir -p "${STORAGE_PATH}/photos"
    log_info "Created photos directory"
  fi

  if [ ! -d "${STORAGE_PATH}/thumbnails" ]; then
    mkdir -p "${STORAGE_PATH}/thumbnails"
    log_info "Created thumbnails directory"
  fi

  if [ ! -d "${STORAGE_PATH}/temp" ]; then
    mkdir -p "${STORAGE_PATH}/temp"
    log_info "Created temp directory"
  fi

  if [ ! -d "${STORAGE_PATH}/logs" ]; then
    mkdir -p "${STORAGE_PATH}/logs"
    log_info "Created logs directory"
  fi

  log_info "Storage directories setup completed"
}

# Setup storage directories
create_storage_dirs

# Initialize application
log_info "Initializing PhotoPrism2..."

# Run database migrations if needed
if [ "${RUN_MIGRATIONS:-true}" = "true" ]; then
  log_info "Running database migrations..."
  # Add migration command here
  # For example: /app/photoprism2 migrate
  log_info "Database migrations completed"
fi

# Set environment-specific configurations
if [ "${NODE_ENV:-production}" = "development" ]; then
  log_info "Running in development mode"
  # Development-specific setup
  export DEBUG=true
elif [ "${NODE_ENV:-production}" = "production" ]; then
  log_info "Running in production mode"
  # Production-specific setup
  export DEBUG=false
fi

# Execute the command provided as argument (CMD)
log_info "Starting application: $*"
exec "$@"
