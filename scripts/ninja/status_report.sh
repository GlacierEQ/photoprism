#!/bin/bash
# Ninja Team Status Reporter
# Provides real-time monitoring of ninja team deployments with GPU/NPU support
# Version: 1.1.0

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build/ninja"
TEAM_SIZE=${1:-12}
REFRESH_INTERVAL=${2:-5}  # Default refresh interval in seconds

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
BOLD='\033[1m'
RESET='\033[0m'

# Function to check if a command is available
check_command() {
    command -v "$1" &> /dev/null
}

# Function to check if jq is available
has_jq() {
    check_command jq
}

# Function to get JSON value with fallback to grep if jq is not available
get_json_value() {
    local file=$1
    local key=$2
    local default=$3

    if has_jq; then
        jq -r ".$key // \"$default\"" "$file" 2>/dev/null || echo "$default"
    else
        grep -o "\"$key\":[^,}]*" "$file" 2>/dev/null | cut -d':' -f2 | tr -d '"' || echo "$default"
    fi
}

# Function to check GPU status
check_gpu_status() {
    echo -e "${BOLD}GPU Status:${RESET}"

    if check_command nvidia-smi; then
        echo "  NVIDIA GPU detected"
        nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader | \
        awk -F', ' '{
            printf "  GPU %s: %s\n", $1, $2;
            printf "    Temperature: %s°C | Utilization: %s | Memory: %s / %s\n", $3, $4, $5, $6;
        }'
        return 0
    elif check_command rocm-smi; then
        echo "  AMD GPU detected"
        rocm-smi --showuse --showmemuse --showtemp | grep -v "===" | sed 's/^/  /'
        return 0
    else
        echo -e "  ${YELLOW}No GPU detected or drivers not installed${RESET}"
        return 1
    fi
}

# Function to check NPU status
check_npu_status() {
    echo -e "${BOLD}NPU Status:${RESET}"

    if check_command mlaunch; then
        echo "  NPU detected (mlaunch)"
        mlaunch status | grep -v "===" | sed 's/^/  /'
        return 0
    elif check_command edgetpu_runtime; then
        echo "  Google Edge TPU detected"
        edgetpu_runtime --list | sed 's/^/  /'
        return 0
    elif [ -d "/sys/class/mcu/mcu0" ]; then
        echo "  System NPU detected"
        if [ -f "/sys/class/mcu/mcu0/status" ]; then
            echo -n "  Status: "
            cat /sys/class/mcu/mcu0/status
        fi
        return 0
    else
        echo -e "  ${YELLOW}No NPU detected${RESET}"
        return 1
    fi
}

# Function to display the full status report
display_status_report() {
    # Clear screen for each refresh
    clear

    # Print header
    echo -e "${CYAN}===== PHOTOPRISM NINJA TEAM STATUS REPORT =====${RESET}"
    echo -e "${CYAN}Date: $(date +"%Y-%m-%d %H:%M:%S")${RESET}"
    echo

    # Display overall deployment status
    DEPLOYMENT_STATUS_FILE="${BUILD_DIR}/deployment-status.json"
    if [ -f "$DEPLOYMENT_STATUS_FILE" ]; then
        status=$(get_json_value "$DEPLOYMENT_STATUS_FILE" "status" "Unknown")
        environment=$(get_json_value "$DEPLOYMENT_STATUS_FILE" "environment" "Unknown")
        timestamp=$(get_json_value "$DEPLOYMENT_STATUS_FILE" "timestamp" "Unknown")

        # Set color based on status
        status_color=""
        case "$status" in
            "ready"|"completed"|"success") status_color="${GREEN}" ;;
            "in_progress"|"running") status_color="${BLUE}" ;;
            "failed"|"error") status_color="${RED}" ;;
            *) status_color="" ;;
        esac

        echo -e "${BOLD}Deployment Status:${RESET} ${status_color}${status}${RESET}"
        echo -e "${BOLD}Environment:${RESET} ${environment}"
        echo -e "${BOLD}Last Update:${RESET} ${timestamp}"
    else
        echo -e "${YELLOW}No deployment status found${RESET}"
    fi

    echo
    echo -e "${CYAN}----- TEAM STATUS -----${RESET}"

    # Display team statuses in table format
    printf "%-8s %-15s %-15s %-15s %-20s\n" "TEAM ID" "STATUS" "COMPLETED" "FAILED" "CURRENT TASK"
    echo "--------------------------------------------------------------------------------"

    # Track team statistics
    local active_teams=0
    local completed_teams=0
    local failed_teams=0

    for team_id in $(seq 1 ${TEAM_SIZE}); do
        status_file="${BUILD_DIR}/teams/team-${team_id}/status.json"
        if [ -f "${status_file}" ]; then
            team_status=$(get_json_value "$status_file" "status" "Unknown")
            tasks_completed=$(get_json_value "$status_file" "tasks_completed" "0")
            tasks_failed=$(get_json_value "$status_file" "tasks_failed" "0")
            current_task=$(get_json_value "$status_file" "current_task" "none")

            # Truncate current_task if too long
            if [ ${#current_task} -gt 20 ]; then
                current_task="${current_task:0:17}..."
            fi

            # Set color based on status and update counters
            status_color=""
            case "$team_status" in
                "ready"|"completed"|"initialized")
                    status_color="${GREEN}"
                    ((completed_teams++))
                    ;;
                "busy"|"running")
                    status_color="${BLUE}"
                    ((active_teams++))
                    ;;
                "failed"|"error")
                    status_color="${RED}"
                    ((failed_teams++))
                    ;;
                *) status_color="" ;;
            esac

            printf "%-8s ${status_color}%-15s${RESET} %-15s %-15s %-20s\n" \
                "Team $team_id" "$team_status" "$tasks_completed" "$tasks_failed" "$current_task"
        else
            printf "%-8s ${YELLOW}%-15s${RESET} %-15s %-15s %-20s\n" \
                "Team $team_id" "Not found" "-" "-" "-"
        fi
    done

    # Display team summary
    echo
    echo -e "${BOLD}Summary:${RESET} ${BLUE}$active_teams Active${RESET}, ${GREEN}$completed_teams Completed${RESET}, ${RED}$failed_teams Failed${RESET}"

    echo
    echo -e "${CYAN}----- SYSTEM RESOURCES -----${RESET}"

    # Display system resources
    echo -e "${BOLD}CPU Usage:${RESET}"
    if check_command top; then
        top -bn1 | grep "Cpu(s)" | awk '{print "  " $0}'
    else
        echo "  CPU information not available"
    fi

    echo -e "\n${BOLD}Memory Usage:${RESET}"
    if check_command free; then
        free -h | grep "Mem:" | awk '{printf "  %s used of %s total (%.1f%%)\n", $3, $2, $3/$2*100}'
        free -h | grep "Swap:" | awk '{printf "  Swap: %s used of %s total\n", $3, $2}'
    else
        echo "  Memory information not available"
    fi

    echo -e "\n${BOLD}Disk Usage:${RESET}"
    if check_command df; then
        df -h | grep -E "/$|/home" | awk '{printf "  %s: %s used of %s total (%s)\n", $6, $3, $2, $5}'
    else
        echo "  Disk information not available"
    fi

    # Display GPU status
    echo
    check_gpu_status

    # Display NPU status
    echo
    check_npu_status

    echo
    echo -e "${CYAN}Monitoring ${TEAM_SIZE} teams. Refresh interval: ${REFRESH_INTERVAL}s. Press Ctrl+C to exit.${RESET}"
}

# Trap Ctrl+C to exit gracefully
trap "echo -e '\n${GREEN}Exiting Ninja Team Status Reporter${RESET}'; exit 0" INT

# Main loop for continuous monitoring
while true; do
    display_status_report
    sleep ${REFRESH_INTERVAL}
done
