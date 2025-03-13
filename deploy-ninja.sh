#!/bin/bash
# PhotoPrism Professional Ninja Team Deployment Launcher
# Orchestrates the full deployment process with advanced monitoring, benchmarking, and reporting

# Strict error handling
set -euo pipefail
IFS=$'\n\t'

# Configuration
TEAM_SIZE=12
RECURSION_DEPTH=4
BUILD_MODE="parallel"
LOG_LEVEL="info"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build/ninja"
LOG_FILE="${BUILD_DIR}/logs/deployment-$(date +"%Y%m%d-%H%M%S").log"
DEPLOYMENT_ID="deploy-$(date +%s)"
CONFIG_FILE="${SCRIPT_DIR}/scripts/ninja/cmake/config/team-config.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# Create necessary directories
mkdir -p "${BUILD_DIR}/logs"

# Log function with colorized output
log() {
    local level="$1"
    local message="$2"
    local color=""
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    case "${level}" in
        "INFO") color="${GREEN}" ;;
        "WARN") color="${YELLOW}" ;;
        "ERROR") color="${RED}" ;;
        "DEBUG") color="${CYAN}" ;;
        "START") color="${BLUE}" ;;
        "SUCCESS") color="${GREEN}" ;;
        *) color="${RESET}" ;;
    esac

    echo -e "${color}[${timestamp}] [${level}]${RESET} ${message}" | tee -a "${LOG_FILE}"
}

# Banner display function
show_banner() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BLUE}║${RESET} ${BOLD}PhotoPrism Ninja Team Deployment${RESET}                           ${BLUE}║${RESET}"
    echo -e "${BLUE}║${RESET} ${CYAN}Professional Edition${RESET}                                       ${BLUE}║${RESET}"
    echo -e "${BLUE}╟────────────────────────────────────────────────────────────────╢${RESET}"
    echo -e "${BLUE}║${RESET} Team Size:       ${GREEN}${TEAM_SIZE}${RESET}                                     ${BLUE}║${RESET}"
    echo -e "${BLUE}║${RESET} Recursion Depth: ${GREEN}${RECURSION_DEPTH}${RESET}                                      ${BLUE}║${RESET}"
    echo -e "${BLUE}║${RESET} Build Mode:      ${GREEN}${BUILD_MODE}${RESET}                                ${BLUE}║${RESET}"
    echo -e "${BLUE}║${RESET} Deployment ID:   ${GREEN}${DEPLOYMENT_ID}${RESET}                ${BLUE}║${RESET}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${RESET}"
    echo
}

# Error handling
handle_error() {
    local line_number="$1"
    local error_code="${2:-1}"
    log "ERROR" "Deployment failed at line ${line_number} with exit code ${error_code}"
    log "ERROR" "Check the log file at ${LOG_FILE} for more details"
    echo
    echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${RED}║${RESET} ${BOLD}DEPLOYMENT FAILED${RESET}                                           ${RED}║${RESET}"
    echo -e "${RED}║${RESET} See log file for details: ${LOG_FILE}              ${RED}║${RESET}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${RESET}"
    exit "$error_code"
}

# Set up error trap
trap 'handle_error $LINENO $?' ERR

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."

    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        log "ERROR" "Docker is not installed. Please install Docker before proceeding."
        exit 1
    fi

    # Check if Docker Compose is installed
    if ! command -v docker compose &> /dev/null && ! command -v docker-compose &> /dev/null; then
        log "ERROR" "Docker Compose is not installed. Please install Docker Compose before proceeding."
        exit 1
    fi

    # Check if CMake is installed
    if ! command -v cmake &> /dev/null; then
        log "WARN" "CMake is not installed. Some advanced features may not work correctly."
    fi

    # Check if Ninja build system is installed
    if ! command -v ninja &> /dev/null; then
        log "WARN" "Ninja build system is not installed. Falling back to default build system."
    fi

    # Check if jq is installed (for JSON processing)
    if ! command -v jq &> /dev/null; then
        log "WARN" "jq is not installed. Some JSON processing features may not work correctly."
    fi

    log "SUCCESS" "Prerequisites check passed"
}

# Initialize environment
initialize_environment() {
    log "START" "Initializing environment..."

    # Create necessary directories
    mkdir -p "${BUILD_DIR}/team"
    mkdir -p "${BUILD_DIR}/logs"
    mkdir -p "${BUILD_DIR}/artifacts"
    mkdir -p "${BUILD_DIR}/cache"
    mkdir -p "${BUILD_DIR}/reports"

    # Setup configuration
    if [ ! -f "${CONFIG_FILE}" ]; then
        log "INFO" "Creating default configuration..."
        mkdir -p "$(dirname "${CONFIG_FILE}")"

        # Create default config file
        cat > "${CONFIG_FILE}" << EOF
{
  "team": {
    "name": "PhotoPrism Ninja Team",
    "size": ${TEAM_SIZE},
    "recursion_depth": ${RECURSION_DEPTH},
    "build_mode": "${BUILD_MODE}"
  },
  "resources": {
    "memory_per_ninja": "4G",
    "cpu_per_ninja": 2,
    "max_disk_usage": "50G"
  },
  "logging": {
    "level": "${LOG_LEVEL}",
    "format": "json",
    "output": ["file", "console"]
  },
  "monitoring": {
    "enabled": true,
    "metrics_endpoint": "http://localhost:9090/metrics",
    "dashboard_url": "http://localhost:3000"
  },
  "deployment": {
    "strategies": ["rolling", "blue-green", "canary"],
    "default_strategy": "rolling",
    "auto_rollback": true
  }
}
EOF
    fi

    # Create team directories
    for member_id in $(seq 1 ${TEAM_SIZE}); do
        member_dir="${BUILD_DIR}/team/member-${member_id}"
        mkdir -p "${member_dir}/workspace"
        mkdir -p "${member_dir}/logs"
        mkdir -p "${member_dir}/cache"
        mkdir -p "${member_dir}/benchmarks"

        # Initialize member status
        cat > "${member_dir}/status.json" << EOF
{
  "member_id": ${member_id},
  "status": "initialized",
  "last_updated": "$(date +"%Y-%m-%d %H:%M:%S")",
  "tasks_completed": 0,
  "tasks_failed": 0
}
EOF
    done

    # Initialize deployment status
    cat > "${BUILD_DIR}/deployment-status.json" << EOF
{
  "deployment_id": "${DEPLOYMENT_ID}",
  "status": "initializing",
  "team_size": ${TEAM_SIZE},
  "recursion_depth": ${RECURSION_DEPTH},
  "start_time": "$(date +"%Y-%m-%d %H:%M:%S")",
  "build_mode": "${BUILD_MODE}"
}
EOF

    log "SUCCESS" "Environment initialized successfully"
}

# Update deployment status
update_deployment_status() {
    local status="$1"
    local message="${2:-}"

    cat > "${BUILD_DIR}/deployment-status.json" << EOF
{
  "deployment_id": "${DEPLOYMENT_ID}",
  "status": "${status}",
  "message": "${message}",
  "team_size": ${TEAM_SIZE},
  "recursion_depth": ${RECURSION_DEPTH},
  "last_updated": "$(date +"%Y-%m-%d %H:%M:%S")",
  "build_mode": "${BUILD_MODE}"
}
EOF
}

# Start monitoring
start_monitoring() {
    log "START" "Starting deployment monitoring..."

    # Create monitoring directory if it doesn't exist
    mkdir -p "${BUILD_DIR}/monitoring"

    # Start monitoring in the background
    (
        while true; do
            # Collect system metrics
            date "+%Y-%m-%d %H:%M:%S" > "${BUILD_DIR}/monitoring/timestamp.txt"

            # CPU usage
            if command -v mpstat &> /dev/null; then
                mpstat 1 1 | grep -A 5 "%idle" | tail -n 1 > "${BUILD_DIR}/monitoring/cpu.txt"
            fi

            # Memory usage
            if command -v free &> /dev/null; then
                free -h > "${BUILD_DIR}/monitoring/memory.txt"
            fi

            # Disk usage
            df -h "${BUILD_DIR}" > "${BUILD_DIR}/monitoring/disk.txt"

            # Team status
            local active_members=0
            local completed_tasks=0
            local failed_tasks=0

            for member_id in $(seq 1 ${TEAM_SIZE}); do
                if [ -f "${BUILD_DIR}/team/member-${member_id}/status.json" ]; then
                    if grep -q '"status": "busy"' "${BUILD_DIR}/team/member-${member_id}/status.json"; then
                        active_members=$((active_members + 1))
                    fi

                    # Extract task counts if jq is available
                    if command -v jq &> /dev/null; then
                        completed=$(jq -r '.tasks_completed // 0' "${BUILD_DIR}/team/member-${member_id}/status.json")
                        failed=$(jq -r '.tasks_failed // 0' "${BUILD_DIR}/team/member-${member_id}/status.json")

                        completed_tasks=$((completed_tasks + completed))
                        failed_tasks=$((failed_tasks + failed))
                    fi
                fi
            done

            # Write team status to monitoring file
            cat > "${BUILD_DIR}/monitoring/team_status.json" << EOF
{
  "active_members": ${active_members},
  "total_members": ${TEAM_SIZE},
  "completed_tasks": ${completed_tasks},
  "failed_tasks": ${failed_tasks},
  "timestamp": "$(date +"%Y-%m-%d %H:%M:%S")"
}
EOF

            # Sleep for 5 seconds before next collection
            sleep 5

            # Check if deployment is still running
            if [ ! -f "${BUILD_DIR}/monitoring/continue" ]; then
                break
            fi
        done
    ) &

    # Store monitoring process ID
    echo $! > "${BUILD_DIR}/monitoring/pid.txt"

    # Create continue flag
    touch "${BUILD_DIR}/monitoring/continue"

    log "SUCCESS" "Monitoring started"
}

# Stop monitoring
stop_monitoring() {
    log "INFO" "Stopping monitoring..."

    # Remove continue flag
    if [ -f "${BUILD_DIR}/monitoring/continue" ]; then
        rm "${BUILD_DIR}/monitoring/continue"
    fi

    # Kill monitoring process if it exists
    if [ -f "${BUILD_DIR}/monitoring/pid.txt" ]; then
        pid=$(cat "${BUILD_DIR}/monitoring/pid.txt")
        if ps -p $pid > /dev/null; then
            kill $pid 2>/dev/null || true
        fi
        rm "${BUILD_DIR}/monitoring/pid.txt"
    fi

    log "SUCCESS" "Monitoring stopped"
}

# Launch deployment
launch_deployment() {
    log "START" "Starting ninja team deployment..."
    update_deployment_status "deploying" "Deploying with ${TEAM_SIZE} ninja team members"

    # Execute the deployment script
    "${SCRIPT_DIR}/scripts/ninja/cmake/ninja-team-deploy.sh" ${TEAM_SIZE} ${RECURSION_DEPTH}

    log "SUCCESS" "Ninja team deployment completed"
    update_deployment_status "deployed" "Deployment completed successfully"
}

# Generate deployment report
generate_report() {
    log "INFO" "Generating deployment report..."

    # Create report directory
    mkdir -p "${BUILD_DIR}/reports"

    # Report filename
    local report_file="${BUILD_DIR}/reports/deployment-report-$(date +"%Y%m%d-%H%M%S").html"

    # Generate HTML report
    cat > "${report_file}" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PhotoPrism Ninja Team Deployment Report</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 20px;
            color: #333;
            max-width: 1200px;
            margin: 0 auto;
        }
        header {
            background-color: #0078d7;
            color: white;
            padding: 20px;
            border-radius: 5px;
            margin-bottom: 20px;
        }
        h1 {
            margin: 0;
        }
        .summary {
            background-color: #f5f5f5;
            padding: 15px;
            border-radius: 5px;
            margin-bottom: 20px;
        }
        .success {
            color: #2e7d32;
            font-weight: bold;
        }
        .failure {
            color: #c62828;
            font-weight: bold;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 20px;
        }
        th, td {
            border: 1px solid #ddd;
            padding: 8px;
            text-align: left;
        }
        th {
            background-color: #f2f2f2;
        }
        tr:nth-child(even) {
            background-color: #f9f9f9;
        }
        .metrics {
            display: flex;
            justify-content: space-between;
            flex-wrap: wrap;
        }
        .metric-card {
            flex-basis: 30%;
            background-color: #f5f5f5;
            padding: 15px;
            border-radius: 5px;
            margin-bottom: 20px;
        }
        footer {
            text-align: center;
            margin-top: 40px;
            color: #666;
            font-size: 0.9em;
        }
    </style>
</head>
<body>
    <header>
        <h1>PhotoPrism Ninja Team Deployment Report</h1>
        <p>Generated on $(date +"%Y-%m-%d %H:%M:%S")</p>
    </header>

    <div class="summary">
        <h2>Deployment Summary</h2>
        <p><strong>Deployment ID:</strong> ${DEPLOYMENT_ID}</p>
        <p><strong>Status:</strong> <span class="success">Completed</span></p>
        <p><strong>Team Size:</strong> ${TEAM_SIZE} ninjas</p>
        <p><strong>Recursion Depth:</strong> ${RECURSION_DEPTH}</p>
        <p><strong>Build Mode:</strong> ${BUILD_MODE}</p>
    </div>

    <h2>Team Performance</h2>
    <table>
        <tr>
            <th>Ninja Member</th>
            <th>Tasks Completed</th>
            <th>Tasks Failed</th>
            <th>Performance Score</th>
        </tr>
EOF

    # Add team member stats to report
    total_completed=0
    total_failed=0

    for member_id in $(seq 1 ${TEAM_SIZE}); do
        if [ -f "${BUILD_DIR}/team/member-${member_id}/status.json" ] && command -v jq &> /dev/null; then
            completed=$(jq -r '.tasks_completed // 0' "${BUILD_DIR}/team/member-${member_id}/status.json")
            failed=$(jq -r '.tasks_failed // 0' "${BUILD_DIR}/team/member-${member_id}/status.json")

            # Calculate performance score (just an example formula)
            if [ "$completed" -gt 0 ] || [ "$failed" -gt 0 ]; then
                total=$((completed + failed))
                score=$(( (completed * 100) / (total > 0 ? total : 1) ))
            else
                score=0
            fi

            total_completed=$((total_completed + completed))
            total_failed=$((total_failed + failed))

            cat >> "${report_file}" << EOF
        <tr>
            <td>Ninja ${member_id}</td>
            <td>${completed}</td>
            <td>${failed}</td>
            <td>${score}%</td>
        </tr>
EOF
        else
            cat >> "${report_file}" << EOF
        <tr>
            <td>Ninja ${member_id}</td>
            <td>N/A</td>
            <td>N/A</td>
            <td>N/A</td>
        </tr>
EOF
        fi
    done

    # Complete the HTML report
    cat >> "${report_file}" << EOF
    </table>

    <div class="metrics">
        <div class="metric-card">
            <h3>Total Tasks</h3>
            <p><strong>Completed:</strong> ${total_completed}</p>
            <p><strong>Failed:</strong> ${total_failed}</p>
            <p><strong>Success Rate:</strong> $(( (total_completed * 100) / ((total_completed + total_failed) > 0 ? (total_completed + total_failed) : 1) ))%</p>
        </div>

        <div class="metric-card">
            <h3>Deployment Time</h3>
            <p><strong>Start:</strong> ${deployment_start_time}</p>
            <p><strong>End:</strong> $(date +"%Y-%m-%d %H:%M:%S")</p>
        </div>

        <div class="metric-card">
            <h3>Next Steps</h3>
            <p>PhotoPrism should be available at: <a href="http://localhost:2342/">http://localhost:2342/</a></p>
        </div>
    </div>

    <footer>
        <p>Generated by the PhotoPrism Ninja Team Deployment System</p>
        <p>© $(date +"%Y") PhotoPrism</p>
    </footer>
</body>
</html>
EOF

    log "SUCCESS" "Deployment report generated: ${report_file}"

    # Open the report if in a desktop environment
    if command -v xdg-open &> /dev/null; then
        xdg-open "${report_file}" &> /dev/null || true
    elif command -v open &> /dev/null; then
        open "${report_file}" &> /dev/null || true
    elif command -v start &> /dev/null; then
        start "${report_file}" &> /dev/null || true
    fi
}

# Main function
main() {
    show_banner

    # Store deployment start time
    deployment_start_time=$(date +"%Y-%m-%d %H:%M:%S")

    check_prerequisites
    initialize_environment
    start_monitoring

    # Launch deployment
    launch_deployment

    # Stop monitoring
    stop_monitoring

    # Generate report
    generate_report

    echo
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}║${RESET} ${BOLD}DEPLOYMENT COMPLETED SUCCESSFULLY${RESET}                         ${GREEN}║${RESET}"
    echo -e "${GREEN}║${RESET} PhotoPrism is now available at: ${CYAN}http://localhost:2342/${RESET}       ${GREEN}║${RESET}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${RESET}"
}

# Run the main function
main
