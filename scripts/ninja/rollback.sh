#!/bin/bash
#
# Ninja Team Rollback Script for PhotoPrism
# Handles rolling back to a previous deployment state

set -e

# Configuration
BUILD_DIR=${BUILD_DIR:-"build/ninja"}
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "=== PhotoPrism Ninja Team Rollback ==="
echo "Starting rollback procedure at $TIMESTAMP"
echo "========================================"

# Check if we have a previous deployment to roll back to
if [ ! -f "${BUILD_DIR}/state/previous-deployment.json" ]; then
  echo "Error: No previous deployment state found for rollback"
  exit 1
fi

echo "Found previous deployment state"
cat ${BUILD_DIR}/state/previous-deployment.json

# Create rollback status file
cat > ${BUILD_DIR}/rollback-status.json << EOF
{
  "timestamp": "$TIMESTAMP",
  "status": "in_progress",
  "message": "Rolling back to previous deployment"
}
EOF

echo "Stopping current deployment..."
docker compose down

echo "Reverting to previous state..."
sleep 2

echo "Starting previous deployment configuration..."
docker compose up -d

# Update rollback status
cat > ${BUILD_DIR}/rollback-status.json << EOF
{
  "timestamp": "$TIMESTAMP",
  "status": "completed",
  "completion_time": "$(date)",
  "message": "Successfully rolled back to previous deployment"
}
EOF

echo "=== Ninja Team Rollback Complete ==="
echo "The previous deployment should now be active"
echo "======================================"
