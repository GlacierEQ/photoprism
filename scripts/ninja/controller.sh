#!/bin/bash
# Ninja Team Deployment Controller
# Orchestrates coordinated deployments with multiple ninja teams

set -euo pipefail
IFS=$'\n\t'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_DIR="${PROJECT_ROOT}/scripts/ninja/config"
BUILD_DIR="${PROJECT_ROOT}/build/ninja"
LOG_DIR="${BUILD_DIR}/logs"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
LOG_FILE="${LOG_DIR}/ninja-controller-${TIMESTAMP}.log"
DEPLOYMENT_ID="deploy-${TIMESTAMP}"

# Default settings
COMMAND=${1:-"deploy"}
TEAM_SIZE=${TEAM_SIZE:-12}
RECURSION_DEPTH=${RECURSION_DEPTH:-4}
BUILD_MODE=${BUILD_MODE:-"parallel"}
ENVIRONMENT=${ENVIRONMENT:-"production"}
CONFIG_FILE=${CONFIG_FILE:-"${CONFIG_DIR}/deploy-config.json"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# Create necessary directories
mkdir -p "${CONFIG_DIR}"
mkdir -p "${LOG_DIR}"

# Log function
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local log_message="[${timestamp}] [${level}] ${message}"

    # Color output based on level
    case "${level}" in
        "INFO")  echo -e "${GREEN}${log_message}${RESET}" ;;
        "WARN")  echo -e "${YELLOW}${log_message}${RESET}" ;;
        "ERROR") echo -e "${RED}${log_message}${RESET}" ;;
        "DEBUG") echo -e "${BLUE}${log_message}${RESET}" ;;
        *)       echo -e "${log_message}" ;;
    esac

    # Write to log file
    echo "${log_message}" >> "${LOG_FILE}"
}

# Error handler
handle_error() {
    local line_number="$1"
    local error_code="${2:-1}"
    log "ERROR" "Deployment failed at line ${line_number} with exit code ${error_code}"
    log "ERROR" "See log file at ${LOG_FILE} for details"
    exit "$error_code"
}

trap 'handle_error $LINENO $?' ERR

# Load configuration file
load_config() {
    log "INFO" "Loading configuration from ${CONFIG_FILE}"

    if [ -f "${CONFIG_FILE}" ]; then
        if command -v jq &> /dev/null; then
            TEAM_SIZE=$(jq -r '.deployment.team.size // 12' "${CONFIG_FILE}")
            RECURSION_DEPTH=$(jq -r '.deployment.team.recursion_depth // 4' "${CONFIG_FILE}")
            BUILD_MODE=$(jq -r '.deployment.team.build_mode // "parallel"' "${CONFIG_FILE}")
        else
            log "WARN" "jq not found, using default configuration"
        fi
    else
        log "WARN" "Configuration file not found, using default settings"
    fi

    # Set environment-specific settings
    case "${ENVIRONMENT}" in
        "production")
            log "INFO" "Using production environment settings"
            ;;
        "staging")
            log "INFO" "Using staging environment settings"
            ;;
        "development")
            log "INFO" "Using development environment settings"
            RECURSION_DEPTH=2  # Reduce recursion depth for development
            ;;
        *)
            log "WARN" "Unknown environment: ${ENVIRONMENT}, using default settings"
            ;;
    esac

    log "INFO" "Configuration loaded: Team Size=${TEAM_SIZE}, Recursion Depth=${RECURSION_DEPTH}, Build Mode=${BUILD_MODE}"
}

# Show banner
show_banner() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${RESET} ${BOLD}PhotoPrism Ninja Team Controller${RESET}                          ${CYAN}║${RESET}"
    echo -e "${CYAN}║${RESET} Command: ${YELLOW}${COMMAND}${RESET}                                          ${CYAN}║${RESET}"
    echo -e "${CYAN}╟────────────────────────────────────────────────────────────────╢${RESET}"
    echo -e "${CYAN}║${RESET} Teams:           ${GREEN}${TEAM_SIZE}${RESET}                                      ${CYAN}║${RESET}"
    echo -e "${CYAN}║${RESET} Recursion Depth: ${GREEN}${RECURSION_DEPTH}${RESET}                                      ${CYAN}║${RESET}"
    echo -e "${CYAN}║${RESET} Build Mode:      ${GREEN}${BUILD_MODE}${RESET}                                ${CYAN}║${RESET}"
    echo -e "${CYAN}║${RESET} Environment:     ${GREEN}${ENVIRONMENT}${RESET}                             ${CYAN}║${RESET}"
    echo -e "${CYAN}║${RESET} Deployment ID:   ${GREEN}${DEPLOYMENT_ID}${RESET}                 ${CYAN}║${RESET}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${RESET}"
    echo
}

# Initialize environment
initialize_environment() {
    log "INFO" "Initializing environment..."

    # Create directories
    mkdir -p "${BUILD_DIR}/teams"
    mkdir -p "${BUILD_DIR}/artifacts"
    mkdir -p "${BUILD_DIR}/monitoring"

    # Create deployment status file
    cat > "${BUILD_DIR}/deployment-status.json" << EOF
{
  "deployment_id": "${DEPLOYMENT_ID}",
  "command": "${COMMAND}",
  "status": "initializing",
  "timestamp": "$(date +"%Y-%m-%d %H:%M:%S")",
  "environment": "${ENVIRONMENT}",
  "team_size": ${TEAM_SIZE},
  "recursion_depth": ${RECURSION_DEPTH},
  "build_mode": "${BUILD_MODE}"
}
EOF

    # Create teams
    for team_id in $(seq 1 ${TEAM_SIZE}); do
        team_dir="${BUILD_DIR}/teams/team-${team_id}"
        mkdir -p "${team_dir}/workspace"
        mkdir -p "${team_dir}/logs"
        mkdir -p "${team_dir}/artifacts"

        # Initialize team status
        cat > "${team_dir}/status.json" << EOF
{
  "team_id": ${team_id},
  "status": "initialized",
  "tasks_completed": 0,
  "tasks_failed": 0,
  "recursion_level": 0,
  "last_updated": "$(date +"%Y-%m-%d %H:%M:%S")"
}
EOF
    done

    log "INFO" "Environment initialized successfully"
}

# Update deployment status
update_status() {
    local status="$1"
    local message="${2:-}"

    cat > "${BUILD_DIR}/deployment-status.json" << EOF
{
  "deployment_id": "${DEPLOYMENT_ID}",
  "command": "${COMMAND}",
  "status": "${status}",
  "message": "${message}",
  "timestamp": "$(date +"%Y-%m-%d %H:%M:%S")",
  "environment": "${ENVIRONMENT}",
  "team_size": ${TEAM_SIZE},
  "recursion_depth": ${RECURSION_DEPTH},
  "build_mode": "${BUILD_MODE}"
}
EOF
}

# Deploy with ninja teams
deploy() {
    log "INFO" "Starting deployment with ${TEAM_SIZE} ninja teams..."
    update_status "deploying" "Deploying with ${TEAM_SIZE} ninja teams"

    # Call the deployment script
    "${SCRIPT_DIR}/cmake/ninja-team-deploy.sh" ${TEAM_SIZE} ${RECURSION_DEPTH} ${BUILD_MODE} ${ENVIRONMENT}

    log "INFO" "Deployment completed successfully"
    update_status "deployed" "Deployment completed successfully"
}

# Rollback to previous deployment
rollback() {
    log "INFO" "Starting rollback operation..."
    update_status "rolling-back" "Rolling back to previous deployment"

    # Call rollback script
    "${SCRIPT_DIR}/rollback.sh"

    log "INFO" "Rollback completed"
    update_status "rolled-back" "Rollback completed successfully"
}

# Check deployment status
status() {
    log "INFO" "Checking deployment status..."

    if [ -f "${BUILD_DIR}/deployment-status.json" ]; then
        if command -v jq &> /dev/null; then
            jq '.' "${BUILD_DIR}/deployment-status.json"
        else
            cat "${BUILD_DIR}/deployment-status.json"
        fi
    else
        log "WARN" "No deployment status file found"
    fi

    # Show team statuses
    echo -e "\n${BOLD}Team Statuses:${RESET}"
    for team_id in $(seq 1 ${TEAM_SIZE}); do
        status_file="${BUILD_DIR}/teams/team-${team_id}/status.json"
        if [ -f "${status_file}" ]; then
            if command -v jq &> /dev/null; then
                team_status=$(jq -r '.status' "${status_file}")
                tasks_completed=$(jq -r '.tasks_completed' "${status_file}")
                tasks_failed=$(jq -r '.tasks_failed' "${status_file}")
                echo -e "Team ${team_id}: Status=${team_status}, Completed=${tasks_completed}, Failed=${tasks_failed}"
            else
                echo -e "Team ${team_id}: $(cat "${status_file}" | tr -d '\n' | tr -d ' ')"
            fi
        else
            echo -e "Team ${team_id}: Status unknown"
        fi
    done
}

# Clean up previous deployments
cleanup() {
    log "INFO" "Cleaning up previous deployments..."

    # Confirm cleanup
    read -p "This will remove all build artifacts. Continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "Cleanup cancelled"
        return
    fi

    update_status "cleaning" "Cleaning previous deployments"

    # Remove team directories
    rm -rf "${BUILD_DIR}/teams"

    # Remove artifacts
    rm -rf "${BUILD_DIR}/artifacts"

    # Keep logs but archive them
    if [ -d "${BUILD_DIR}/logs" ]; then
        archive_name="logs-archive-$(date +"%Y%m%d-%H%M%S").tar.gz"
        tar -czf "${BUILD_DIR}/${archive_name}" -C "${BUILD_DIR}" logs
        rm -rf "${BUILD_DIR}/logs"
        mkdir -p "${BUILD_DIR}/logs"
    fi

    log "INFO" "Cleanup completed"
    update_status "cleaned" "Previous deployments cleaned up"
}

# Generate deployment report
generate_report() {
    log "INFO" "Generating deployment report..."

    # Create report directory
    mkdir -p "${BUILD_DIR}/reports"

    # Report filename
    local report_file="${BUILD_DIR}/reports/deployment-report-${TIMESTAMP}.html"

    # Get deployment status
    local deployment_status="Unknown"
    local deployment_time="Unknown"
    if [ -f "${BUILD_DIR}/deployment-status.json" ] && command -v jq &> /dev/null; then
        deployment_status=$(jq -r '.status' "${BUILD_DIR}/deployment-status.json")
        deployment_time=$(jq -r '.timestamp' "${BUILD_DIR}/deployment-status.json")
    fi

    # Generate HTML report
    cat > "${report_file}" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PhotoPrism Ninja Team Deployment Report</title>
    <style>
        body { font-family: system-ui, -apple-system, sans-serif; line-height: 1.6; margin: 0; padding: 20px; color: #333; max-width: 1200px; margin: 0 auto; }
        header { background-color: #0078d7; color: white; padding: 20px; border-radius: 5px; margin-bottom: 20px; }
        h1 { margin: 0; }
        .summary { background-color: #f5f5f5; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        .success { color: #2e7d32; font-weight: bold; }
        .failure { color: #c62828; font-weight: bold; }
        table { width: 100%; border-collapse: collapse; margin-bottom: 20px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        .metrics { display: flex; justify-content: space-between; flex-wrap: wrap; }
        .metric-card { flex-basis: 30%; background-color: #f5f5f5; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        footer { text-align: center; margin-top: 40px; color: #666; font-size: 0.9em; }
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
        <p><strong>Status:</strong> <span class="${deployment_status == "deployed" ? "success" : "failure"}">${deployment_status}</span></p>
        <p><strong>Environment:</strong> ${ENVIRONMENT}</p>
        <p><strong>Team Size:</strong> ${TEAM_SIZE}</p>
        <p><strong>Recursion Depth:</strong> ${RECURSION_DEPTH}</p>
        <p><strong>Build Mode:</strong> ${BUILD_MODE}</p>
        <p><strong>Timestamp:</strong> ${deployment_time}</p>
    </div>

    <h2>Team Performance</h2>
    <table>
        <tr>
            <th>Team ID</th>
            <th>Status</th>
            <th>Tasks Completed</th>
            <th>Tasks Failed</th>
            <th>Performance Score</th>
        </tr>
EOF

    # Add team data to report
    local total_completed=0
    local total_failed=0

    for team_id in $(seq 1 ${TEAM_SIZE}); do
        local status_file="${BUILD_DIR}/teams/team-${team_id}/status.json"
        local team_status="Unknown"
        local tasks_completed=0
        local tasks_failed=0
        local performance=0

        if [ -f "${status_file}" ] && command -v jq &> /dev/null; then
            team_status=$(jq -r '.status' "${status_file}")
            tasks_completed=$(jq -r '.tasks_completed // 0' "${status_file}")
            tasks_failed=$(jq -r '.tasks_failed // 0' "${status_file}")

            # Calculate performance score
            local total_tasks=$((tasks_completed + tasks_failed))
            if [ "$total_tasks" -gt 0 ]; then
                performance=$((tasks_completed * 100 / total_tasks))
            fi

            total_completed=$((total_completed + tasks_completed))
            total_failed=$((total_failed + tasks_failed))
        fi

        cat >> "${report_file}" << EOF
        <tr>
            <td>Team ${team_id}</td>
            <td>${team_status}</td>
            <td>${tasks_completed}</td>
            <td>${tasks_failed}</td>
            <td>${performance}%</td>
        </tr>
EOF
    done

    # Complete the HTML report
    cat >> "${report_file}" << EOF
    </table>

    <div class="metrics">
        <div class="metric-card">
            <h3>Task Statistics</h3>
            <p><strong>Total Completed:</strong> ${total_completed}</p>
            <p><strong>Total Failed:</strong> ${total_failed}</p>
            <p><strong>Success Rate:</strong> $([ $((total_completed + total_failed)) -gt 0 ] && echo $((total_completed * 100 / (total_completed + total_failed))) || echo "N/A")%</p>
        </div>

        <div class="metric-card">
            <h3>Deployment Information</h3>
            <p><strong>Time:</strong> ${deployment_time}</p>
            <p><strong>Log File:</strong> ${LOG_FILE}</p>
        </div>

        <div class="metric-card">
            <h3>Next Steps</h3>
            <p>PhotoPrism should be available at: <a href="http://localhost:2342/">http://localhost:2342/</a></p>
            <p>Run status check: <code>./scripts/ninja/controller.sh status</code></p>
        </div>
    </div>

    <footer>
        <p>Generated by the PhotoPrism Ninja Team Controller</p>
        <p>&copy; $(date +"%Y") PhotoPrism</p>
    </footer>
</body>
</html>
EOF

    log "INFO" "Report generated: ${report_file}"

    # Open the report if in a desktop environment
    if command -v xdg-open &> /dev/null; then
        xdg-open "${report_file}" &> /dev/null || true
    elif command -v open &> /dev/null; then
        open "${report_file}" &> /dev/null || true
    elif command -v start &> /dev/null; then
        start "${report_file}" &> /dev/null || true
    fi
}

# Execute monitoring dashboard
monitor() {
    log "INFO" "Starting monitoring dashboard..."

    # Create monitoring directory if it doesn't exist
    mkdir -p "${BUILD_DIR}/monitoring"

    # Check prerequisites
    if ! command -v watch &> /dev/null; then
        log "ERROR" "The 'watch' command is required for monitoring."
        return 1
    fi

    # Start watching status
    watch -n 2 -c "${SCRIPT_DIR}/status_report.sh ${TEAM_SIZE}"
}

# Main execution
main() {
    load_config
    show_banner

    case "${COMMAND}" in
        "deploy")
            initialize_environment
            deploy
            generate_report
            ;;
        "status")
            status
            ;;
        "rollback")
            rollback
            ;;
        "cleanup")
            cleanup
            ;;
        "report")
            generate_report
            ;;
        "monitor")
            monitor
            ;;
        *)
            log "ERROR" "Unknown command: ${COMMAND}"
            echo "Usage: $0 [deploy|status|rollback|cleanup|report|monitor]"
            exit 1
            ;;
    esac
}

# Execute main function
main
