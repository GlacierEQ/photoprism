#!/bin/bash
# Ninja Team Monitoring Script
# Monitors resources and deployment status of Ninja Team

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build/ninja"
LOG_DIR="${BUILD_DIR}/logs"
METRICS_DIR="${BUILD_DIR}/metrics"
CONFIG_FILE="${PROJECT_ROOT}/config/ninja/team-config.yml"
INTERVAL=${MONITORING_INTERVAL:-10}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Ensure directories exist
mkdir -p "${LOG_DIR}"
mkdir -p "${METRICS_DIR}"

# Log function
log() {
  echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_DIR}/monitoring.log"
}

# Monitor container metrics
monitor_containers() {
  log "${BLUE}Collecting container metrics...${NC}"

  # Check if docker stats command is available
  if ! command -v docker &> /dev/null; then
    log "${RED}Docker command not found${NC}"
    return 1
  fi

  # Get list of containers
  local containers=$(docker ps --format "{{.Names}}" 2>/dev/null)
  if [ -z "$containers" ]; then
    log "${YELLOW}No running containers found${NC}"
    return 0
  fi

  # Clear previous metrics
  local metrics_file="${METRICS_DIR}/container_metrics.json"
  echo "[" > "$metrics_file"

  # Collect metrics for each container
  local first=true
  for container in $containers; do
    # Get container stats in JSON format
    local stats=$(docker stats --no-stream --format "{{json .}}" "$container" 2>/dev/null)

    # Append to metrics file
    if [ "$first" = true ]; then
      first=false
    else
      echo "," >> "$metrics_file"
    fi
    echo "$stats" >> "$metrics_file"
  done

  echo "]" >> "$metrics_file"
  log "${GREEN}Container metrics collected${NC}"
}

# Monitor team status
monitor_team_status() {
  log "${BLUE}Collecting team status...${NC}"

  local team_size=$(grep -oP 'size:\s*\K\d+' "$CONFIG_FILE" 2>/dev/null || echo 4)
  local active_members=0
  local completed_tasks=0
  local failed_tasks=0

  # Collect status from each team member
  for i in $(seq 1 "$team_size"); do
    if [ -f "${BUILD_DIR}/ninja-$i/status.json" ]; then
      local status=$(grep -oP '"status":\s*"\K[^"]+' "${BUILD_DIR}/ninja-$i/status.json" 2>/dev/null)

      if [ "$status" = "busy" ]; then
        active_members=$((active_members + 1))
      fi

      # Count completed and failed tasks if available
      if [ -f "${BUILD_DIR}/ninja-$i/tasks.json" ]; then
        local completed=$(grep -c '"status":"completed"' "${BUILD_DIR}/ninja-$i/tasks.json" 2>/dev/null || echo 0)
        local failed=$(grep -c '"status":"failed"' "${BUILD_DIR}/ninja-$i/tasks.json" 2>/dev/null || echo 0)

        completed_tasks=$((completed_tasks + completed))
        failed_tasks=$((failed_tasks + failed))
      fi
    fi
  done

  # Write team status to file
  local status_file="${METRICS_DIR}/team_status.json"
  cat > "$status_file" << EOF
{
  "timestamp": "$(date +"%Y-%m-%d %H:%M:%S")",
  "team_size": $team_size,
  "active_members": $active_members,
  "idle_members": $((team_size - active_members)),
  "completed_tasks": $completed_tasks,
  "failed_tasks": $failed_tasks
}
EOF

  log "${GREEN}Team status collected${NC}"
}

# Monitor system resources
monitor_system() {
  log "${BLUE}Collecting system metrics...${NC}"

  local metrics_file="${METRICS_DIR}/system_metrics.json"

  # Get CPU usage
  local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')

  # Get memory usage
  local mem_total=$(free -m | awk '/^Mem:/{print $2}')
  local mem_used=$(free -m | awk '/^Mem:/{print $3}')
  local mem_usage=$(awk "BEGIN {printf \"%.2f\", $mem_used/$mem_total*100}")

  # Get disk usage
  local disk_usage=$(df -h / | awk '/\//{print $(NF-1)}' | sed 's/%//')

  # Write system metrics to file
  cat > "$metrics_file" << EOF
{
  "timestamp": "$(date +"%Y-%m-%d %H:%M:%S")",
  "cpu_usage": $cpu_usage,
  "memory": {
    "total": $mem_total,
    "used": $mem_used,
    "usage_percent": $mem_usage
  },
  "disk_usage_percent": $disk_usage
}
EOF

  log "${GREEN}System metrics collected${NC}"
}

# Display monitoring dashboard
display_dashboard() {
  clear
  echo -e "${CYAN}============================================${NC}"
  echo -e "${CYAN}   PHOTOPRISM NINJA TEAM MONITORING        ${NC}"
  echo -e "${CYAN}============================================${NC}"
  echo ""
  echo -e "${BLUE}Time:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""

  # Display system metrics
  if [ -f "${METRICS_DIR}/system_metrics.json" ]; then
    local cpu=$(grep -oP '"cpu_usage":\s*\K[0-9.]+' "${METRICS_DIR}/system_metrics.json" 2>/dev/null)
    local mem=$(grep -oP '"usage_percent":\s*\K[0-9.]+' "${METRICS_DIR}/system_metrics.json" 2>/dev/null)
    local disk=$(grep -oP '"disk_usage_percent":\s*\K[0-9.]+' "${METRICS_DIR}/system_metrics.json" 2>/dev/null)

    echo -e "${BLUE}System Metrics:${NC}"
    echo -e "  CPU Usage: ${cpu}%"
    echo -e "  Memory Usage: ${mem}%"
    echo -e "  Disk Usage: ${disk}%"
    echo ""
  fi

  # Display team status
  if [ -f "${METRICS_DIR}/team_status.json" ]; then
    local team_size=$(grep -oP '"team_size":\s*\K[0-9]+' "${METRICS_DIR}/team_status.json" 2>/dev/null)
    local active=$(grep -oP '"active_members":\s*\K[0-9]+' "${METRICS_DIR}/team_status.json" 2>/dev/null)
    local completed=$(grep -oP '"completed_tasks":\s*\K[0-9]+' "${METRICS_DIR}/team_status.json" 2>/dev/null)
    local failed=$(grep -oP '"failed_tasks":\s*\K[0-9]+' "${METRICS_DIR}/team_status.json" 2>/dev/null)

    echo -e "${BLUE}Team Status:${NC}"
    echo -e "  Team Size: ${team_size}"
    echo -e "  Active Members: ${active}"
    echo -e "  Completed Tasks: ${completed}"
    echo -e "  Failed Tasks: ${failed}"
    echo ""
  fi

  # Display individual ninja status
  echo -e "${BLUE}Ninja Status:${NC}"
  local team_size=$(grep -oP 'size:\s*\K\d+' "$CONFIG_FILE" 2>/dev/null || echo 4)
  for i in $(seq 1 "$team_size"); do
    if [ -f "${BUILD_DIR}/ninja-$i/status.json" ]; then
      local specialty=$(grep -oP '"specialty":\s*"\K[^"]+' "${BUILD_DIR}/ninja-$i/status.json" 2>/dev/null)
      local status=$(grep -oP '"status":\s*"\K[^"]+' "${BUILD_DIR}/ninja-$i/status.json" 2>/dev/null)
      local task=$(grep -oP '"last_task":\s*"\K[^"]+' "${BUILD_DIR}/ninja-$i/status.json" 2>/dev/null)

      echo -e "  Ninja $i ($specialty): ${status}"
      if [ "$status" = "busy" ] && [ "$task" != "null" ]; then
        echo -e "    Task: ${task}"
      fi
    else
      echo -e "  Ninja $i: Not initialized"
    fi
  done
  echo ""

  # Display deployment status
  if [ -f "${BUILD_DIR}/deployment-status.json" ]; then
    local status=$(grep -oP '"status":\s*"\K[^"]+' "${BUILD_DIR}/deployment-status.json" 2>/dev/null)
    local message=$(grep -oP '"message":\s*"\K[^"]+' "${BUILD_DIR}/deployment-status.json" 2>/dev/null)

    echo -e "${BLUE}Deployment Status:${NC} ${status}"
    if [ -n "$message" ]; then
      echo -e "  $message"
    fi
  fi
}

# Main monitoring loop
main() {
  log "${GREEN}Starting Ninja Team monitoring${NC}"
  log "Monitoring interval: ${INTERVAL}s"

  # Create a flag file to indicate monitoring is active
  touch "${BUILD_DIR}/monitoring_active"

  # Trap for cleanup
  trap cleanup EXIT INT TERM

  # Main monitoring loop
  while [ -f "${BUILD_DIR}/monitoring_active" ]; do
    # Collect metrics
    monitor_system || true
    monitor_team_status || true
    monitor_containers || true

    # Display dashboard
    display_dashboard

    # Wait for next interval
    sleep "${INTERVAL}"
  done
}

# Cleanup on exit
cleanup() {
  log "${YELLOW}Stopping monitoring${NC}"
  rm -f "${BUILD_DIR}/monitoring_active"
}

# Start the monitoring
main
