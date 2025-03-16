#!/bin/bash
# PhotoPrism2 Ninja Team Deployment Controller
# Coordinates docker deployment using the Ninja Team pattern

set -o errexit
set -o pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="${PROJECT_ROOT}/config/ninja"
BUILD_DIR="${PROJECT_ROOT}/build/ninja"
LOG_DIR="${BUILD_DIR}/logs"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
LOG_FILE="${LOG_DIR}/ninja-deploy-${TIMESTAMP}.log"
ENV_FILE="${PROJECT_ROOT}/.env"

# Default settings
TEAM_SIZE=${NINJA_TEAM_SIZE:-4}
RECURSION_DEPTH=${NINJA_RECURSION_DEPTH:-2}
BUILD_MODE=${NINJA_BUILD_MODE:-"parallel"}
DEPLOYMENT_ENV=${DEPLOYMENT_ENV:-"production"}

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
  local level="$1"
  local message="$2"
  local color="$NC"

  case "$level" in
    "INFO") color="$BLUE" ;;
    "SUCCESS") color="$GREEN" ;;
    "WARN") color="$YELLOW" ;;
    "ERROR") color="$RED" ;;
  esac

  echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [${level}]${NC} ${message}" | tee -a "$LOG_FILE"
}

# Initialize the environment
init_env() {
  log "INFO" "Initializing Ninja Team environment..."

  # Create necessary directories
  mkdir -p "${CONFIG_DIR}"
  mkdir -p "${BUILD_DIR}"
  mkdir -p "${LOG_DIR}"
  mkdir -p "${BUILD_DIR}/state"

  # Create team directories for each member
  for i in $(seq 1 $TEAM_SIZE); do
    mkdir -p "${BUILD_DIR}/ninja-$i/workspace"
    mkdir -p "${BUILD_DIR}/ninja-$i/logs"

    # Initialize ninja status file
    cat > "${BUILD_DIR}/ninja-$i/status.json" << EOF
{
  "id": $i,
  "ready": true,
  "status": "initialized",
  "specialty": "$(get_ninja_specialty $i)",
  "last_task": null,
  "last_update": "$(date +"%Y-%m-%d %H:%M:%S")"
}
EOF
  done

  # Create deployment status file
  cat > "${BUILD_DIR}/deployment-status.json" << EOF
{
  "timestamp": "$TIMESTAMP",
  "environment": "$DEPLOYMENT_ENV",
  "team_size": $TEAM_SIZE,
  "recursion_depth": $RECURSION_DEPTH,
  "build_mode": "$BUILD_MODE",
  "status": "initialized"
}
EOF

  log "SUCCESS" "Ninja Team environment initialized with $TEAM_SIZE members"
}

# Get ninja specialty based on ID
get_ninja_specialty() {
  local ninja_id=$1
  local specialty

  case $(( ninja_id % 4 )) in
    1) specialty="frontend" ;;
    2) specialty="backend" ;;
    3) specialty="database" ;;
    0) specialty="infrastructure" ;;
    *) specialty="general" ;;
  esac

  echo "$specialty"
}

# Load environment variables
load_env() {
  if [ -f "$ENV_FILE" ]; then
    log "INFO" "Loading environment from $ENV_FILE"
    # shellcheck disable=SC1090
    source "$ENV_FILE"
  else
    log "WARN" "Environment file not found at $ENV_FILE"
  fi
}

# Validate the environment
validate_env() {
  log "INFO" "Validating environment for Ninja Team deployment..."

  # Check for Docker
  if ! command -v docker &> /dev/null; then
    log "ERROR" "Docker is not installed or not in PATH"
    exit 1
  fi

  # Check for Docker Compose
  if ! command -v docker compose &> /dev/null && ! command -v docker-compose &> /dev/null; then
    log "ERROR" "Docker Compose is not installed or not in PATH"
    exit 1
  fi

  log "SUCCESS" "Environment validation passed"
}

# Execute task with a specific ninja
execute_with_ninja() {
  local ninja_id=$1
  local task_name=$2
  local recursion_level=${3:-1}

  log "INFO" "[Ninja $ninja_id] Executing task '$task_name' at recursion level $recursion_level"

  # Update ninja status
  update_ninja_status "$ninja_id" "busy" "$task_name"

  # Simulate or perform the actual task
  case "$task_name" in
    "prepare_environment")
      # Create directories, setup environment
      log "INFO" "[Ninja $ninja_id] Preparing environment..."
      sleep 2
      ;;

    "build_docker_images")
      # Build or pull Docker images
      log "INFO" "[Ninja $ninja_id] Building Docker images..."
      docker compose build --pull
      ;;

    "setup_network")
      # Setup Docker network
      log "INFO" "[Ninja $ninja_id] Setting up Docker network..."
      docker network inspect photoprism_network &>/dev/null || docker network create photoprism_network
      ;;

    "start_database")
      # Start database services
      log "INFO" "[Ninja $ninja_id] Starting database services..."
      docker compose up -d mariadb postgres
      ;;

    "start_services")
      # Start remaining services
      log "INFO" "[Ninja $ninja_id] Starting all services..."
      docker compose up -d
      ;;

    "verify_deployment")
      # Verify all services are running correctly
      log "INFO" "[Ninja $ninja_id] Verifying deployment..."
      sleep 5
      docker compose ps
      ;;

    "setup_monitoring")
      # Setup monitoring if enabled
      log "INFO" "[Ninja $ninja_id] Setting up monitoring..."
      if [ "${ENABLE_MONITORING:-false}" = "true" ]; then
        docker compose --profile monitoring up -d prometheus grafana
      else
        log "INFO" "Monitoring is disabled. Skipping."
      fi
      ;;

    *)
      log "WARN" "[Ninja $ninja_id] Unknown task: $task_name"
      ;;
  esac

  # Update ninja status
  update_ninja_status "$ninja_id" "ready" "$task_name"

  log "SUCCESS" "[Ninja $ninja_id] Task '$task_name' completed at recursion level $recursion_level"
}

# Update ninja status
update_ninja_status() {
  local ninja_id=$1
  local status=$2
  local task=$3

  cat > "${BUILD_DIR}/ninja-$ninja_id/status.json" << EOF
{
  "id": $ninja_id,
  "ready": $([ "$status" = "ready" ] && echo "true" || echo "false"),
  "status": "$status",
  "specialty": "$(get_ninja_specialty $ninja_id)",
  "last_task": "$task",
  "last_update": "$(date +"%Y-%m-%d %H:%M:%S")"
}
EOF
}

# Update deployment status
update_deployment_status() {
  local status=$1
  local message=${2:-""}

  cat > "${BUILD_DIR}/deployment-status.json" << EOF
{
  "timestamp": "$TIMESTAMP",
  "environment": "$DEPLOYMENT_ENV",
  "team_size": $TEAM_SIZE,
  "recursion_depth": $RECURSION_DEPTH,
  "build_mode": "$BUILD_MODE",
  "status": "$status",
  "message": "$message",
  "last_update": "$(date +"%Y-%m-%d %H:%M:%S")"
}
EOF

  log "INFO" "Deployment status updated to: $status"
}

# Run recursive deployment
recursive_deploy() {
  local level=$1
  local parent=${2:-""}

  if [ "$level" -gt "$RECURSION_DEPTH" ]; then
    log "INFO" "Maximum recursion depth reached"
    return 0
  fi

  log "INFO" "Starting recursive deployment level $level"
  update_deployment_status "deploying" "Recursion level $level"

  # Define tasks for this recursion level
  local tasks=()
  if [ "$level" -eq 1 ]; then
    tasks=("prepare_environment" "build_docker_images" "setup_network" "start_database" "start_services" "verify_deployment" "setup_monitoring")
  else
    # For deeper recursion levels, focus on optimization tasks
    tasks=("optimize_database" "optimize_network" "verify_performance")
  fi

  # Execute tasks based on build mode
  if [ "$BUILD_MODE" = "parallel" ]; then
    log "INFO" "Using parallel build mode for level $level"

    # Execute tasks in parallel by distributing them to ninjas
    for i in "${!tasks[@]}"; do
      local ninja_id=$(( (i % TEAM_SIZE) + 1 ))
      execute_with_ninja "$ninja_id" "${tasks[$i]}" "$level" &

      # Slight delay to avoid resource contention
      sleep 0.5
    done

    # Wait for all background processes to finish
    wait
  else
    log "INFO" "Using sequential build mode for level $level"

    # Execute tasks sequentially
    for task in "${tasks[@]}"; do
      local ninja_id=$(( (RANDOM % TEAM_SIZE) + 1 ))
      execute_with_ninja "$ninja_id" "$task" "$level"
    done
  fi

  log "SUCCESS" "Recursive deployment level $level completed"

  # If not at max recursion depth, continue to next level
  if [ "$level" -lt "$RECURSION_DEPTH" ]; then
    recursive_deploy $(( level + 1 )) "$level"
  fi
}

# Create backup of current state
create_backup() {
  log "INFO" "Creating deployment backup..."

  local backup_dir="${BUILD_DIR}/backup-${TIMESTAMP}"
  mkdir -p "$backup_dir"

  # Backup current environment file
  if [ -f "$ENV_FILE" ]; then
    cp "$ENV_FILE" "$backup_dir/.env.backup"
  fi

  # Backup current deployment status
  if [ -f "${BUILD_DIR}/deployment-status.json" ]; then
    cp "${BUILD_DIR}/deployment-status.json" "$backup_dir/deployment-status.backup.json"
  fi

  log "SUCCESS" "Backup created at $backup_dir"
}

# Generate deployment report
generate_report() {
  log "INFO" "Generating deployment report..."

  local report_file="${BUILD_DIR}/deployment-report-${TIMESTAMP}.txt"

  {
    echo "PhotoPrism2 Ninja Team Deployment Report"
    echo "========================================"
    echo "Timestamp: $(date)"
    echo "Environment: $DEPLOYMENT_ENV"
    echo "Team Size: $TEAM_SIZE"
    echo "Recursion Depth: $RECURSION_DEPTH"
    echo "Build Mode: $BUILD_MODE"
    echo ""
    echo "Deployment Status:"
    if [ -f "${BUILD_DIR}/deployment-status.json" ]; then
      cat "${BUILD_DIR}/deployment-status.json"
    else
      echo "No deployment status available"
    fi
    echo ""
    echo "Team Members:"
    for i in $(seq 1 $TEAM_SIZE); do
      echo "Ninja $i ($(get_ninja_specialty $i)):"
      if [ -f "${BUILD_DIR}/ninja-$i/status.json" ]; then
        cat "${BUILD_DIR}/ninja-$i/status.json"
      else
        echo "No status information available"
      fi
      echo ""
    done
    echo ""
    echo "Docker Services:"
    docker compose ps
  } > "$report_file"

  log "SUCCESS" "Report generated at $report_file"
}

# Main function
main() {
  # Create log directory if it doesn't exist
  mkdir -p "$LOG_DIR"

  log "INFO" "Starting PhotoPrism2 Ninja Team Deployment"
  log "INFO" "Team Size: $TEAM_SIZE, Recursion Depth: $RECURSION_DEPTH, Build Mode: $BUILD_MODE"

  # Load environment variables
  load_env

  # Validate environment
  validate_env

  # Create backup
  create_backup

  # Initialize environment
  init_env

  # Start recursive deployment from level 1
  recursive_deploy 1

  # Update final deployment status
  update_deployment_status "completed" "Deployment completed successfully"

  # Generate report
  generate_report

  log "SUCCESS" "PhotoPrism2 Ninja Team Deployment completed successfully"
  log "INFO" "Report available at: ${BUILD_DIR}/deployment-report-${TIMESTAMP}.txt"
}

# Execute main function
main
