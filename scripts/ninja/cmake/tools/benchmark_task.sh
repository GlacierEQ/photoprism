#!/bin/bash
# benchmark_task.sh - Performance benchmarking script for ninja team tasks
# Used by ninja_team_task function with NINJA_BENCHMARK_ENABLED=ON

set -e

TASK_NAME="$1"
BUILD_DIR="${CMAKE_BINARY_DIR:-./build}"
BENCHMARK_DIR="${BUILD_DIR}/benchmarks"
TEAM_DIR="${BUILD_DIR}/team"

if [ -z "${TASK_NAME}" ]; then
    echo "Error: Task name not provided."
    echo "Usage: $0 <task_name>"
    exit 1
fi

echo "=== Benchmarking task: ${TASK_NAME} ==="
echo "Started at: $(date)"

# Ensure benchmark directory exists
mkdir -p "${BENCHMARK_DIR}"

BENCHMARK_FILE="${BENCHMARK_DIR}/${TASK_NAME}_benchmark.json"
BENCHMARK_REPORT="${BENCHMARK_DIR}/${TASK_NAME}_benchmark_report.txt"

# Initialize benchmark data
echo "{
  \"task\": \"${TASK_NAME}\",
  \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",
  \"members\": [],
  \"summary\": {
    \"total_time\": 0,
    \"avg_time_per_member\": 0,
    \"min_time\": 0,
    \"max_time\": 0,
    \"std_deviation\": 0
  }
}" > "${BENCHMARK_FILE}"

# Collect performance data from each team member
team_size=$(find "${TEAM_DIR}" -maxdepth 1 -name "member-*" -type d | wc -l)
echo "Team size: ${team_size}"

# Arrays to store benchmark data
declare -a execution_times
declare -a member_ids
declare -a subtask_counts

# Collect data from status files
total_time=0
min_time=9999999
max_time=0

for member_dir in "${TEAM_DIR}"/member-*; do
    if [ ! -d "${member_dir}" ]; then
        continue
    fi

    member_id=$(basename "${member_dir}" | sed 's/member-//')
    status_file="${member_dir}/status.json"
    log_file="${member_dir}/logs/${TASK_NAME}.log"

    if [ ! -f "${status_file}" ]; then
        echo "Warning: Status file not found for member ${member_id}"
        continue
    fi

    # Extract data from log file
    if [ -f "${log_file}" ]; then
        start_time=$(grep "Start Time:" "${log_file}" | head -1 | cut -d ':' -f 2- | xargs)
        end_time=$(grep "End Time:" "${log_file}" | head -1 | cut -d ':' -f 2- | xargs)

        # Convert to seconds if dates are available
        if [ -n "${start_time}" ] && [ -n "${end_time}" ]; then
            if command -v date >/dev/null 2>&1; then
                start_sec=$(date -d "${start_time}" +%s 2>/dev/null || date -j -f "%a %b %d %T %Z %Y" "${start_time}" +%s 2>/dev/null || echo 0)
                end_sec=$(date -d "${end_time}" +%s 2>/dev/null || date -j -f "%a %b %d %T %Z %Y" "${end_time}" +%s 2>/dev/null || echo 0)
                execution_time=$((end_sec - start_sec))
            else
                # Fallback to parsing log for execution time
                execution_time=$(grep "Completed subtask" "${log_file}" | grep "seconds" | awk '{sum += $4} END {print sum}')
            fi
        else
            # Fallback to estimate
            execution_time=$(grep "Completed subtask" "${log_file}" | grep "seconds" | awk '{sum += $4} END {print sum}')
        fi

        # If we couldn't extract time, use a default
        if [ -z "${execution_time}" ] || [ "${execution_time}" -eq 0 ]; then
            echo "Warning: Could not determine execution time for member ${member_id}, using estimate"
            execution_time=1
        fi

        # Extract subtask count
        subtask_count=$(grep "Subtask" "${log_file}" | grep "Executing subtask" | wc -l)
        if [ "${subtask_count}" -eq 0 ]; then
            # Fallback to parsing status file
            subtask_count=$(grep -o '"subtasks":[^,}]*' "${status_file}" | cut -d ':' -f 2)
        fi

        if [ -z "${subtask_count}" ]; then
            subtask_count=1
        fi
    else
        echo "Warning: Log file not found for member ${member_id} task ${TASK_NAME}"
        execution_time=1
        subtask_count=1
    fi

    # Store data
    execution_times+=($execution_time)
    member_ids+=($member_id)
    subtask_counts+=($subtask_count)

    # Update aggregates
    total_time=$((total_time + execution_time))
    if [ "${execution_time}" -lt "${min_time}" ]; then
        min_time=${execution_time}
    fi
    if [ "${execution_time}" -gt "${max_time}" ]; then
        max_time=${execution_time}
    fi

    # Add member data to JSON
    # Use temporary file to build the members array
    temp_file=$(mktemp)
    jq ".members += [{
        \"member_id\": ${member_id},
        \"execution_time\": ${execution_time},
        \"subtasks\": ${subtask_count},
        \"time_per_subtask\": $(echo "scale=2; ${execution_time} / ${subtask_count}" | bc)
    }]" "${BENCHMARK_FILE}" > "${temp_file}" 2>/dev/null || {
        # Fallback if jq is not available
        sed -i.bak "s/\"members\": \[/\"members\": \[{\"member_id\": ${member_id}, \"execution_time\": ${execution_time}, \"subtasks\": ${subtask_count}, \"time_per_subtask\": $(echo "scale=2; ${execution_time} / ${subtask_count}" | bc)},/g" "${BENCHMARK_FILE}"
        rm -f "${BENCHMARK_FILE}.bak"
        continue
    }
    mv "${temp_file}" "${BENCHMARK_FILE}"
done

# Calculate average time
if [ "${team_size}" -gt 0 ]; then
    avg_time=$(echo "scale=2; ${total_time} / ${team_size}" | bc)
else
    avg_time=0
fi

# Calculate standard deviation
sum_squared_diff=0
for time in "${execution_times[@]}"; do
    diff=$(echo "scale=2; ${time} - ${avg_time}" | bc)
    squared_diff=$(echo "scale=2; ${diff} * ${diff}" | bc)
    sum_squared_diff=$(echo "scale=2; ${sum_squared_diff} + ${squared_diff}" | bc)
done

if [ "${team_size}" -gt 1 ]; then
    std_deviation=$(echo "scale=2; sqrt(${sum_squared_diff} / (${team_size} - 1))" | bc)
else
    std_deviation=0
fi

# Update summary in JSON
temp_file=$(mktemp)
jq ".summary = {
    \"total_time\": ${total_time},
    \"avg_time_per_member\": ${avg_time},
    \"min_time\": ${min_time},
    \"max_time\": ${max_time},
    \"std_deviation\": ${std_deviation}
}" "${BENCHMARK_FILE}" > "${temp_file}" 2>/dev/null || {
    # Fallback if jq is not available
    sed -i.bak "s/\"summary\": {[^}]*}/\"summary\": {\"total_time\": ${total_time}, \"avg_time_per_member\": ${avg_time}, \"min_time\": ${min_time}, \"max_time\": ${max_time}, \"std_deviation\": ${std_deviation}}/g" "${BENCHMARK_FILE}"
    rm -f "${BENCHMARK_FILE}.bak"
}
[ -f "${temp_file}" ] && mv "${temp_file}" "${BENCHMARK_FILE}"

# Generate readable report
echo "=== Benchmark Report for Task: ${TASK_NAME} ===" > "${BENCHMARK_REPORT}"
echo "Generated at: $(date)" >> "${BENCHMARK_REPORT}"
echo "-----------------------------------------" >> "${BENCHMARK_REPORT}"
echo "Team size: ${team_size}" >> "${BENCHMARK_REPORT}"
echo "Total execution time: ${total_time} seconds" >> "${BENCHMARK_REPORT}"
echo "Average time per member: ${avg_time} seconds" >> "${BENCHMARK_REPORT}"
echo "Minimum execution time: ${min_time} seconds" >> "${BENCHMARK_REPORT}"
echo "Maximum execution time: ${max_time} seconds" >> "${BENCHMARK_REPORT}"
echo "Standard deviation: ${std_deviation}" >> "${BENCHMARK_REPORT}"
echo "-----------------------------------------" >> "${BENCHMARK_REPORT}"
echo "Member Performance:" >> "${BENCHMARK_REPORT}"

# Sort members by execution time
for i in "${!member_ids[@]}"; do
    echo "${member_ids[$i]} ${execution_times[$i]} ${subtask_counts[$i]}"
done | sort -n -k2 | while read -r id time subtasks; do
    time_per_subtask=$(echo "scale=2; ${time} / ${subtasks}" | bc)
    echo "  Member ${id}: ${time} seconds (${subtasks} subtasks, ${time_per_subtask} sec/subtask)" >> "${BENCHMARK_REPORT}"
done

echo "-----------------------------------------" >> "${BENCHMARK_REPORT}"
echo "Benchmark data saved to: ${BENCHMARK_FILE}" >> "${BENCHMARK_REPORT}"

echo "Benchmark completed at: $(date)"
echo "Report saved to: ${BENCHMARK_REPORT}"

# Display summary report
cat "${BENCHMARK_REPORT}"
