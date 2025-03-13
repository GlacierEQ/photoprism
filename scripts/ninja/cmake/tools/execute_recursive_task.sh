#!/bin/bash
# execute_recursive_task.sh - Recursive task execution script for ninja team members
# Used by the ninja_team_recursive_task function in NinjaTeam.cmake

set -e

# Parse environment variables
MEMBER_ID="${NINJA_MEMBER_ID:-unknown}"
TASK_NAME="${NINJA_TASK_NAME:-unknown}"
RECURSION_LEVEL="${NINJA_RECURSION_LEVEL:-1}"
MAX_RECURSION="${NINJA_MAX_RECURSION:-4}"
MAX_MEMORY="${NINJA_MAX_MEMORY:-1G}"
MAX_CPU="${NINJA_MAX_CPU:-1}"
PARALLEL_JOBS="${NINJA_PARALLEL_JOBS:-1}"

# Set up logging
LOG_DIR="${CMAKE_BINARY_DIR:-./build}/team/member-${MEMBER_ID}/logs"
LOG_FILE="${LOG_DIR}/${TASK_NAME}_level${RECURSION_LEVEL}.log"

echo "=== Ninja Team Member ${MEMBER_ID} ===" > "${LOG_FILE}"
echo "Task: ${TASK_NAME}" >> "${LOG_FILE}"
echo "Recursion Level: ${RECURSION_LEVEL}/${MAX_RECURSION}" >> "${LOG_FILE}"
echo "Parallel Jobs: ${PARALLEL_JOBS}" >> "${LOG_FILE}"
echo "Max Memory: ${MAX_MEMORY}" >> "${LOG_FILE}"
echo "Max CPU: ${MAX_CPU}" >> "${LOG_FILE}"
echo "Start Time: $(date)" >> "${LOG_FILE}"
echo "----------------------------------------" >> "${LOG_FILE}"

# Update status file
STATUS_FILE="${CMAKE_BINARY_DIR:-./build}/team/member-${MEMBER_ID}/status.json"
echo "{
  \"member_id\": ${MEMBER_ID},
  \"status\": \"working\",
  \"task\": \"${TASK_NAME}\",
  \"recursion_level\": ${RECURSION_LEVEL},
  \"max_recursion\": ${MAX_RECURSION},
  \"start_time\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",
  \"tasks\": 0,
  \"performance_score\": 100
}" > "${STATUS_FILE}"

# Calculate work to be done at this recursion level
# Work increases exponentially with recursion level
WORK_FACTOR=$((2 ** (RECURSION_LEVEL - 1)))
TOTAL_WORK=$((PARALLEL_JOBS * WORK_FACTOR))

echo "Executing ${TOTAL_WORK} units of work at recursion level ${RECURSION_LEVEL}" | tee -a "${LOG_FILE}"

# Execute parallel jobs
for ((job=1; job<=${PARALLEL_JOBS}; job++)); do
    (
        JOB_LOG_FILE="${LOG_FILE}.job${job}"
        echo "Starting job ${job}/${PARALLEL_JOBS} for recursion level ${RECURSION_LEVEL}" > "${JOB_LOG_FILE}"

        # Calculate work for this job
        JOB_WORK=$((WORK_FACTOR))

        # Perform work
        for ((i=1; i<=${JOB_WORK}; i++)); do
            echo "Job ${job}: Work unit ${i}/${JOB_WORK} at recursion level ${RECURSION_LEVEL}" >> "${JOB_LOG_FILE}"

            # Simulate CPU-intensive work
            for ((k=1; k<=1000; k++)); do
                result=$((k * k)) > /dev/null
            done

            # Simulate some I/O operations
            echo "Work unit ${i} data" > "${CMAKE_BINARY_DIR:-./build}/team/member-${MEMBER_ID}/workspace/data_${RECURSION_LEVEL}_${job}_${i}.tmp"

            # Update progress
            progress=$((i * 100 / JOB_WORK))
            echo "Progress: ${progress}%" >> "${JOB_LOG_FILE}"

            # Add small delay to prevent overloading
            sleep 0.05
        done

        echo "Completed job ${job} for recursion level ${RECURSION_LEVEL}" >> "${JOB_LOG_FILE}"
    ) &

    # If we want to limit concurrency, we could add a wait here
    if [ $((job % MAX_CPU)) -eq 0 ]; then
        wait
    fi
done

# Wait for all background jobs to complete
wait

# Update status file with completion
echo "{
  \"member_id\": ${MEMBER_ID},
  \"status\": \"completed\",
  \"task\": \"${TASK_NAME}\",
  \"recursion_level\": ${RECURSION_LEVEL},
  \"max_recursion\": ${MAX_RECURSION},
  \"start_time\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",
  \"end_time\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",
  \"tasks\": ${TOTAL_WORK},
  \"performance_score\": 100
}" > "${STATUS_FILE}"

# Clean up temporary files
find "${CMAKE_BINARY_DIR:-./build}/team/member-${MEMBER_ID}/workspace" -name "data_${RECURSION_LEVEL}_*.tmp" -delete

echo "----------------------------------------" >> "${LOG_FILE}"
echo "Task ${TASK_NAME} at recursion level ${RECURSION_LEVEL} completed successfully" >> "${LOG_FILE}"
echo "End Time: $(date)" >> "${LOG_FILE}"

echo "Member ${MEMBER_ID} completed recursive task ${TASK_NAME} level ${RECURSION_LEVEL}"
exit 0
