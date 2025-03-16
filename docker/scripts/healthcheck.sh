#!/bin/bash
set -e

# Default values
HEALTH_ENDPOINT=${HEALTH_ENDPOINT:-"http://localhost:${PORT:-8000}/api/v1/health"}
TIMEOUT=${HEALTH_CHECK_TIMEOUT:-5}

# Function for logging
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [HEALTHCHECK] $1"
}

# Check if curl is available, otherwise use wget
if command -v curl &> /dev/null; then
  log "Checking health endpoint: ${HEALTH_ENDPOINT}"
  response=$(curl -s -o /dev/null -w "%{http_code}" -m ${TIMEOUT} "${HEALTH_ENDPOINT}")

  if [ "$response" = "200" ] || [ "$response" = "204" ]; then
    log "Health check succeeded, status code: ${response}"
    exit 0
  else
    log "Health check failed, status code: ${response}"
    exit 1
  fi
elif command -v wget &> /dev/null; then
  log "Checking health endpoint: ${HEALTH_ENDPOINT}"
  if wget -q -T ${TIMEOUT} -O /dev/null "${HEALTH_ENDPOINT}"; then
    log "Health check succeeded"
    exit 0
  else
    log "Health check failed"
    exit 1
  fi
else
  log "Neither curl nor wget found, cannot perform health check"
  exit 1
fi
