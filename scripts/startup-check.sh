#!/bin/bash
set -e

# Configuration
MIN_MEMORY_GB=2
MIN_DISK_GB=10
REQUIRED_PORTS=(2342 6379 3306)
REQUIRED_SERVICES=(redis mariadb tensorflow)

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

log_error() {
    echo -e "${RED}✗ $1${NC}"
    exit 1
}

# Check system resources
check_resources() {
    echo "Checking system resources..."

    # Memory check
    total_mem=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$total_mem" -lt "$MIN_MEMORY_GB" ]; then
        log_error "Insufficient memory: ${total_mem}GB < ${MIN_MEMORY_GB}GB required"
    fi
    log_success "Memory check passed: ${total_mem}GB available"

    # Disk space check
    available_space=$(df -BG "${PHOTOPRISM_STORAGE_PATH:-/photoprism/storage}" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$available_space" -lt "$MIN_DISK_GB" ]; then
        log_error "Insufficient disk space: ${available_space}GB < ${MIN_DISK_GB}GB required"
    fi
    log_success "Disk space check passed: ${available_space}GB available"
}

# Verify service dependencies
check_services() {
    echo "Verifying service dependencies..."
    for service in "${REQUIRED_SERVICES[@]}"; do
        if ! docker compose ps "$service" | grep -q "Up"; then
            log_error "Service $service is not running"
        fi
        log_success "Service $service is running"
    done
}

# Check network ports
check_ports() {
    echo "Checking required ports..."
    for port in "${REQUIRED_PORTS[@]}"; do
        if netstat -ln | grep -q ":$port "; then
            log_success "Port $port is available"
        else
            log_error "Port $port is not available"
        fi
    done
}

# Additional healthchecks
check_container_logs() {
    echo "Checking container logs for errors..."
    error_count=$(docker compose logs --since 5m | grep -i "error\|exception\|fatal" | wc -l)
    if [ $error_count -gt 0 ]; then
        log_error "Found $error_count errors in recent container logs"
    fi
    log_success "No errors found in container logs"
}

# Main execution
main() {
    echo "Running startup validation..."
    check_resources
    check_services
    check_ports
    check_container_logs
    echo "All startup checks passed successfully"
}

main
