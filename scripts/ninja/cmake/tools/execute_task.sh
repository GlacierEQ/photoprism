#!/bin/bash
# Task execution script for a ninja team member
# Handles the execution of a single task with proper resource management

# Strict error handling
set -euo pipefail
IFS=$'\n\t'

# Expected environment variables
NINJA_MEMBER_ID=${NINJA_MEMBER_ID:-1}
NINJA_TASK_NAME=${NINJA_TASK_NAME:-"unknown_task"}
NINJA_SUBTASKS=${NINJA_SUBTASKS:-1}
NINJA_MAX_MEMORY=${NINJA_MAX_MEMORY:-"1G"}
NINJA_MAX_CPU=${NINJA_MAX_CPU:-1}

# Convert memory string to value in MB
memory_to_mb() {
    local mem="$1"
    local value=$(echo $mem | sed -E 's/([0-9]+)([kKmMgGtT]?).*/\1/')
    local unit=$(echo $mem | sed -E 's/([0-9]+)([kKmMgGtT]?).*/\2/')

    case $unit in
        [gG])
            echo $((value * 1024))
            ;;
        [tT])
            echo $((value * 1024 * 1024))
            ;;
        [kK])
            echo $((value / 1024))
            ;;
        *)
            echo $value
            ;;
    esac
}

# Get absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build/ninja"
MEMBER_DIR="${BUILD_DIR}/team/member-${NINJA_MEMBER_ID}"
LOG_DIR="${MEMBER_DIR}/logs"
LOG_FILE="${LOG_DIR}/${NINJA_TASK_NAME}-$(date +%Y%m%d-%H%M%S).log"
BENCHMARK_FILE="${MEMBER_DIR}/benchmarks/${NINJA_TASK_NAME}-$(date +%Y%m%d-%H%M%S).json"

# Create necessary directories
mkdir -p "${LOG_DIR}"
mkdir -p "${MEMBER_DIR}/benchmarks"

# Log execution
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[${timestamp}] [${level}] [Member ${NINJA_MEMBER_ID}] [Task ${NINJA_TASK_NAME}] ${message}" | tee -a "${LOG_FILE}"
}

# Start benchmarking
start_time=$(date +%s.%N)
log "INFO" "Starting task execution with ${NINJA_SUBTASKS} subtasks"
log "INFO" "Allocated resources: ${NINJA_MAX_MEMORY} memory, ${NINJA_MAX_CPU} CPU cores"

# Update member status
update_status() {
    local status="$1"
    cat > "${MEMBER_DIR}/status.json" << EOF
{
    "member_id": ${NINJA_MEMBER_ID},
    "status": "${status}",
    "task_name": "${NINJA_TASK_NAME}",
    "subtasks": ${NINJA_SUBTASKS},
    "last_updated": "$(date +"%Y-%m-%d %H:%M:%S")",
    "allocated_memory": "${NINJA_MAX_MEMORY}",
    "allocated_cpu": ${NINJA_MAX_CPU}
}
EOF
}

update_status "running"

# Execute task with resource constraints
if command -v cgroup-tools &> /dev/null && [ $(id -u) -eq 0 ]; then
    # Use cgroups if available and running as root
    log "INFO" "Using cgroups for resource constraints"

    # Calculate memory limit in bytes
    memory_mb=$(memory_to_mb "${NINJA_MAX_MEMORY}")
    memory_bytes=$((memory_mb * 1024 * 1024))

    # Create cgroup
    cgcreate -g memory,cpu:ninja_${NINJA_MEMBER_ID}

    # Set limits
    echo $memory_bytes > /sys/fs/cgroup/memory/ninja_${NINJA_MEMBER_ID}/memory.limit_in_bytes
    echo $((NINJA_MAX_CPU * 1000)) > /sys/fs/cgroup/cpu/ninja_${NINJA_MEMBER_ID}/cpu.shares

    # Execute with cgroup
    cgexec -g memory,cpu:ninja_${NINJA_MEMBER_ID} bash -c "
        # Change to workspace directory
        mkdir -p \"${MEMBER_DIR}/workspace/${NINJA_TASK_NAME}\"
        cd \"${MEMBER_DIR}/workspace/${NINJA_TASK_NAME}\"

        # Execute all subtasks
        for subtask in \$(seq 1 ${NINJA_SUBTASKS}); do
            echo \"Executing subtask \${subtask}/${NINJA_SUBTASKS}\"

            # Simulate work based on task name
            case \"${NINJA_TASK_NAME}\" in
                prepare_environment)
                    sleep \$(( (RANDOM % 2) + 1 ))
                    echo \"Environment prepared for subtask \${subtask}\" > \"subtask_\${subtask}.txt\"
                    ;;

                configure_network)
                    sleep \$(( (RANDOM % 3) + 1 ))
                    echo \"Network configured for subtask \${subtask}\" > \"subtask_\${subtask}.txt\"
                    ;;

                setup_database)
                    sleep \$(( (RANDOM % 4) + 2 ))
                    echo \"Database setup for subtask \${subtask}\" > \"subtask_\${subtask}.txt\"
                    ;;

                deploy_services)
                    sleep \$(( (RANDOM % 5) + 3 ))
                    echo \"Services deployed for subtask \${subtask}\" > \"subtask_\${subtask}.txt\"
                    ;;

                verify_deployment)
                    sleep \$(( (RANDOM % 3) + 1 ))
                    echo \"Deployment verified for subtask \${subtask}\" > \"subtask_\${subtask}.txt\"
                    ;;

                setup_monitoring)
                    sleep \$(( (RANDOM % 4) + 2 ))
                    echo \"Monitoring setup for subtask \${subtask}\" > \"subtask_\${subtask}.txt\"
                    ;;

                *)
                    sleep \$(( (RANDOM % 2) + 1 ))
                    echo \"Generic task executed for subtask \${subtask}\" > \"subtask_\${subtask}.txt\"
                    ;;
            esac
        done

        echo \"All ${NINJA_SUBTASKS} subtasks completed successfully\"
    "

    # Clean up cgroup
    cgdelete -g memory,cpu:ninja_${NINJA_MEMBER_ID}
else
    # Fallback to simple execution without resource constraints
    log "INFO" "Executing without cgroups (resource limits will not be enforced)"

    # Change to workspace directory
    mkdir -p "${MEMBER_DIR}/workspace/${NINJA_TASK_NAME}"
    cd "${MEMBER_DIR}/workspace/${NINJA_TASK_NAME}"

    # Execute all subtasks
    for subtask in $(seq 1 ${NINJA_SUBTASKS}); do
        log "INFO" "Executing subtask ${subtask}/${NINJA_SUBTASKS}"

        # Simulate work based on task name
        case "${NINJA_TASK_NAME}" in
            prepare_environment)
                sleep $(( (RANDOM % 2) + 1 ))
                echo "Environment prepared for subtask ${subtask}" > "subtask_${subtask}.txt"
                ;;

            configure_network)
                sleep $(( (RANDOM % 3) + 1 ))
                echo "Network configured for subtask ${subtask}" > "subtask_${subtask}.txt"
                ;;

            setup_database)
                sleep $(( (RANDOM % 4) + 2 ))
                echo "Database setup for subtask ${subtask}" > "subtask_${subtask}.txt"
                ;;

            deploy_services)
                sleep $(( (RANDOM % 5) + 3 ))
                echo "Services deployed for subtask ${subtask}" > "subtask_${subtask}.txt"
                ;;

            verify_deployment)
                sleep $(( (RANDOM % 3) + 1 ))
                echo "Deployment verified for subtask ${subtask}" > "subtask_${subtask}.txt"
                ;;

            setup_monitoring)
                sleep $(( (RANDOM % 4) + 2 ))
                echo "Monitoring setup for subtask ${subtask}" > "subtask_${subtask}.txt"
                ;;

            *)
                sleep $(( (RANDOM % 2) + 1 ))
                echo "Generic task executed for subtask ${subtask}" > "subtask_${subtask}.txt"
                ;;
        esac
    done

    log "INFO" "All ${NINJA_SUBTASKS} subtasks completed successfully"
fi

# Record benchmarking data
end_time=$(date +%s.%N)
execution_time=$(echo "${end_time} - ${start_time}" | bc)

# Create benchmark file
cat > "${BENCHMARK_FILE}" << EOF
{
    "task_name": "${NINJA_TASK_NAME}",
    "member_id": ${NINJA_MEMBER_ID},
    "subtasks": ${NINJA_SUBTASKS},
    "start_time": "${start_time}",
    "end_time": "${end_time}",
    "execution_time": ${execution_time},
    "allocated_memory": "${NINJA_MAX_MEMORY}",
    "allocated_cpu": ${NINJA_MAX_CPU}
}
EOF

log "INFO" "Task execution completed in ${execution_time} seconds"
update_status "completed"

exit 0
