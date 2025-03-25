#!/bin/bash
set -e

# Configuration
IMAGE_NAME="photoprism2"
TAG="latest"
TEST_CONTAINER_NAME="photoprism-verify-$$"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "🔍 Verifying PhotoPrism Docker image ${IMAGE_NAME}:${TAG}"

# Check if image exists
if ! docker image inspect ${IMAGE_NAME}:${TAG} >/dev/null 2>&1; then
    echo -e "${RED}❌ Image ${IMAGE_NAME}:${TAG} not found${NC}"
    exit 1
fi

# Verify image layers and size
echo "📋 Image details:"
docker image inspect ${IMAGE_NAME}:${TAG} --format '{{.Size}}'
docker history ${IMAGE_NAME}:${TAG} --no-trunc --format "{{.Size}}\t{{.CreatedBy}}"

# Test container startup
echo "🚀 Testing container startup..."
docker run --name ${TEST_CONTAINER_NAME} \
    -d \
    -p 2342:2342 \
    --rm \
    ${IMAGE_NAME}:${TAG}

# Wait for container to be healthy
TIMEOUT=30
while [ $TIMEOUT -gt 0 ]; do
    if docker inspect ${TEST_CONTAINER_NAME} --format '{{.State.Health.Status}}' | grep -q "healthy"; then
        echo -e "${GREEN}✅ Container health check passed${NC}"
        break
    fi
    sleep 1
    ((TIMEOUT--))
done

if [ $TIMEOUT -eq 0 ]; then
    echo -e "${RED}❌ Container health check failed${NC}"
    docker logs ${TEST_CONTAINER_NAME}
    docker stop ${TEST_CONTAINER_NAME}
    exit 1
fi

# Verify API endpoint
echo "🌐 Testing API endpoint..."
if curl -sf "http://localhost:2342/api/v1/status" > /dev/null; then
    echo -e "${GREEN}✅ API endpoint test passed${NC}"
else
    echo -e "${RED}❌ API endpoint test failed${NC}"
    docker logs ${TEST_CONTAINER_NAME}
    docker stop ${TEST_CONTAINER_NAME}
    exit 1
fi

# Cleanup
docker stop ${TEST_CONTAINER_NAME}

echo -e "${GREEN}✅ All verification tests passed successfully${NC}"
