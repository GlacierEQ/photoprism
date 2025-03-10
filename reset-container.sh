#!/bin/bash
# Reset and fix container script for PhotoPrism
# This script helps recover from container crashes and fixes common issues

# Stop and remove existing container
echo "Stopping and removing existing PhotoPrism container..."
docker stop photoprism_app 2>/dev/null || true
docker rm photoprism_app 2>/dev/null || true

# Fix line endings in all bash scripts
echo "Fixing line endings in all shell scripts..."
find . -name "*.sh" -type f -exec sed -i 's/\r$//' {} \;

# Reset cached state in Docker
echo "Pruning Docker build cache..."
docker builder prune -f

# Rebuild the Docker image
echo "Rebuilding Docker image..."
docker build --no-cache -t photoprism:latest .

# Start a new container
echo "Starting new container..."
docker run -d -p 2342:2342 -p 3000:3000 \
  -v "$(pwd)/storage:/photoprism/storage" \
  -v "$(pwd)/originals:/photoprism/storage/originals" \
  --name photoprism_app \
  photoprism:latest

echo "Reset completed! Container should be available at http://localhost:2342"
echo "If you still experience issues, check the logs with: docker logs photoprism_app"
