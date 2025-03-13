#!/bin/bash
# monitor_task.sh - Real-time monitoring script for ninja team tasks
# Used by ninja_team_task function with NINJA_MONITOR_ENABLED=ON

set -e

TASK_NAME="$1"
BUILD_DIR="${CMAKE_BINARY_DIR:-./build}"
TEAM_DIR="${BUILD_DIR}/team"
UPDATE_INTERVAL=1  # seconds between updates

if [ -z "${TASK_NAME}" ]; then
    echo "Error: Task name not provided."
    echo "Usage: $0 <task_name>"
    exit 1
fi

# Function to display a progress bar
show_progress() {
    local percent=$1
    local width=50
    local num_filled=$(( width * percent / 100 ))
    local num_empty=$(( width - num_filled ))

    printf "["
    printf "%${num_filled}s" | tr ' ' '#'
    printf "%${num_empty}s" | tr ' ' ' '
    printf "] %3d%%\n" $percent
}

# Function to get status summary from a member
get_member_status() {
    local member_dir=$1
    local member_id=$(basename "${member_dir}" | sed 's/member-//')
    local status_file="${member_dir}/status.json"

    if [ ! -f "${status_file}" ]; then
        echo "Member ${member_id}: No status file found"
        return
    fi

    # Extract status information (basic parsing as jq may not be available)
    local status=$(grep -o '"status":[^,}]*' "${status_file}" | cut -d '"' -f 4)
    local current_task=$(grep -o '"task":[^,}]*' "${status_file}" | cut -d '"' -f 4)

    if [ "${current_task}" != "${TASK_NAME}" ] && [ "${status}" != "initialized" ]; then
        echo "Member ${member_id}: Working on different task (${current_task})"
        return
    fi

    # Look for progress information in the log file
    local log_file="${member_dir}/logs/${TASK_NAME}.log"
    local progress=0
    local subtasks=0
    local completed_subtasks=0

    if [ -f "${log_file}" ]; then
        # Try to extract subtask information
        subtasks=$(grep -o "Subtasks: [0-9]*" "${log_file}" | head -1 | awk '{print $2}')
        completed_subtasks=$(grep "Completed subtask" "${log_file}" | wc -l)

        if [ -n "${subtasks}" ] && [ "${subtasks}" -gt 0 ]; then
            progress=$(( 100 * completed_subtasks / subtasks ))
        else
            # Fallback: try to find progress percentage in the log
            last_progress=$(grep "progress:" "${log_file}" | tail -1 | grep -o "[0-9]*%" | tr -d '%')
            if [ -n "${last_progress}" ]; then
                progress="${last_progress}"
            fi
        fi
    fi

    # Display member status with progress bar
    echo -n "Member ${member_id}: ${status} "
    if [ "${status}" = "working" ]; then
        echo -n "(${completed_subtasks}/${subtasks} subtasks) "
        show_progress ${progress}
    else
        echo "${status}"
    fi
}

# Main monitoring loop
echo "=== Monitoring Task: ${TASK_NAME} ==="
echo "Press Ctrl+C to stop monitoring"
echo ""

while true; do
    clear
    echo "=== Task Monitor: ${TASK_NAME} ==="
    echo "Time: $(date)"
    echo "----------------------------------------"

    # Get list of all team members
    team_members=$(find "${TEAM_DIR}" -maxdepth 1 -name "member-*" -type d | sort)

    # Track overall task completion
    total_members=$(echo "${team_members}" | wc -l)
    completed_members=0

    # Display status for each member
    for member_dir in ${team_members}; do
        # Get and display status
        get_member_status "${member_dir}"

        # Check if this member completed the task
        status_file="${member_dir}/status.json"
        if [ -f "${status_file}" ]; then
            status=$(grep -o '"status":[^,}]*' "${status_file}" | cut -d '"' -f 4)
            task=$(grep -o '"task":[^,}]*' "${status_file}" | cut -d '"' -f 4)
            if [ "${status}" = "completed" ] && [ "${task}" = "${TASK_NAME}" ]; then
                completed_members=$((completed_members + 1))
            fi
        fi
    done

    echo "----------------------------------------"
    # Calculate and show overall progress
    overall_progress=0
    if [ "${total_members}" -gt 0 ]; then
        overall_progress=$(( 100 * completed_members / total_members ))
    fi
    echo -n "Overall Progress: ${completed_members}/${total_members} members completed "
    show_progress ${overall_progress}

    # Check if all members have completed
    if [ "${completed_members}" -eq "${total_members}" ]; then
        echo "✓ Task ${TASK_NAME} completed by all ${total_members} team members!"
        break
    fi

    # Wait before next update
    sleep ${UPDATE_INTERVAL}
done

echo "Monitoring complete."
