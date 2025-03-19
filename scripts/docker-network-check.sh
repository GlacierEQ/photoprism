#!/bin/bash

# Fix relative paths to work from any directory
# Setup logging
LOG_DIR="$(dirname "$(dirname "$0")")/logs"
LOG_FILE="${LOG_DIR}/docker-network-$(date +%Y%m%d-%H%M%S).log"
mkdir -p ${LOG_DIR}

# Load environment variables if available
if [ -f "$(dirname "$(dirname "$0")")/.env.docker" ]; then
  source "$(dirname "$(dirname "$0")")/.env.docker"
fi

log() {
  local level=$1
  local message=$2
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  echo -e "[$timestamp] [$level] $message"
  echo -e "[$timestamp] [$level] $message" >> ${LOG_FILE}
}

log "INFO" "=== Docker Network Diagnostics ==="

# Check for proxy settings
log "INFO" "Checking proxy configuration..."
if [ -n "$http_proxy" ] || [ -n "$https_proxy" ]; then
  log "INFO" "Proxy detected: http_proxy=$http_proxy, https_proxy=$https_proxy"
  export DOCKER_PROXY_ENV="--env http_proxy=$http_proxy --env https_proxy=$https_proxy"
else
  log "INFO" "No proxy settings detected"
fi

# Test Docker Hub connectivity
log "INFO" "Testing connection to Docker Hub..."
start_time=$(date +%s.%N)
curl_result=$(curl -sSL -m 10 https://registry-1.docker.io/v2/ 2>&1) || {
  log "ERROR" "Failed to connect to Docker Hub: $curl_result"
}
end_time=$(date +%s.%N)
execution_time=$(echo "$end_time - $start_time" | bc 2>/dev/null)
if [ -z "$execution_time" ]; then
  execution_time="N/A (bc not installed)"
fi
log "INFO" "Connection test completed in $execution_time seconds"

# Check DNS resolution
log "INFO" "Checking DNS resolution..."
nslookup registry-1.docker.io >> ${LOG_FILE} 2>&1
if [ $? -ne 0 ]; then
  log "ERROR" "DNS resolution failed for registry-1.docker.io"
else
  log "INFO" "DNS resolution successful"
fi

# Check alternative DNS if primary fails
if [ $? -ne 0 ]; then
  log "INFO" "Trying alternative DNS (8.8.8.8)..."
  nslookup registry-1.docker.io 8.8.8.8 >> ${LOG_FILE} 2>&1
fi

# Verify Docker daemon
log "INFO" "Verifying Docker daemon status..."
docker info > /dev/null 2>&1
if [ $? -ne 0 ]; then
  log "ERROR" "Docker daemon not running or not accessible"
else
  log "INFO" "Docker daemon is running"
fi

# Check network connectivity to common registries
log "INFO" "Testing connectivity to common Docker registries..."
for registry in "registry-1.docker.io" "ghcr.io" "quay.io" "gcr.io"; do
  log "INFO" "Checking $registry..."
  if curl -s --connect-timeout 5 https://$registry > /dev/null; then
    log "INFO" "$registry is reachable"
  else
    log "WARNING" "Cannot reach $registry"
  fi
done

# Check Docker Hub rate limits
log "INFO" "Checking Docker Hub rate limits..."
TOKEN=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:ratelimitpreview/test:pull" | jq -r .token 2>/dev/null)

if [ -z "$TOKEN" ] || [ "$TOKEN" == "null" ]; then
  log "ERROR" "Failed to obtain Docker Hub token"
else
  rate_limits=$(curl -s --head -H "Authorization: Bearer $TOKEN" https://registry-1.docker.io/v2/ratelimitpreview/test/manifests/latest)
  remaining=$(echo "$rate_limits" | grep -i "ratelimit-remaining" | cut -d: -f2- | tr -d ' \r')

  if [ -n "$remaining" ]; then
    log "INFO" "Docker Hub rate limit remaining: $remaining"
    if [ "$remaining" -lt 20 ]; then
      log "WARNING" "Docker Hub rate limit is low! Consider authenticating."
    fi
  else
    log "WARNING" "Could not determine rate limit information"
  fi
fi

log "INFO" "Network diagnostics completed - Log saved to ${LOG_FILE}"
echo "Full diagnostics log: ${LOG_FILE}"
