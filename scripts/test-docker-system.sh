#!/bin/bash
set -e

# Test Docker system configuration
echo "Testing Docker system configuration..."

# Check Docker version
docker version || {
    echo "Error: Docker is not running or not installed"
    exit 1
}

# Check Docker Compose version
docker compose version || exit 1

# Check available memory
FREE_MEM=$(free -g | awk '/^Mem:/{print $2}')
if [ $FREE_MEM -lt 2 ]; then
    echo "Warning: Less than 2GB RAM available - performance may be impacted"
fi

# Check storage
STORAGE=$(df -h / | awk '/^\//{print $4}')
echo "Available storage: $STORAGE"

# Test Docker socket
if ! docker info >/dev/null 2>&1; then
    echo "Error: Docker socket not accessible"
    exit 1
fi

# Test container runtime
echo "Testing container runtime..."
docker run --rm hello-world

# Check network connectivity
echo "Testing network connectivity..."
docker network ls

# Verify volume support
echo "Testing volume support..."
docker volume create test-volume
docker volume rm test-volume

# Test container runtime capabilities
echo "Testing container runtime capabilities..."
if command -v podman &> /dev/null; then
    echo "Podman detected, testing..."
    podman info || echo "Podman test failed"
fi

# Verify container networking
echo "Testing container networking..."
docker network create test-network || true
docker run --rm --network test-network alpine ping -c 1 8.8.8.8
docker network rm test-network || true

# Test resource limits
echo "Testing cgroup configuration..."
docker run --rm --memory=100m alpine free -m

# Verify storage drivers
echo "Checking storage drivers..."
docker info | grep "Storage Driver"

# Test Docker Compose compatibility
echo "Testing Docker Compose configuration..."
cat > docker-compose.test.yml <<EOF
version: "3.8"
services:
  test:
    image: hello-world
EOF
docker compose -f docker-compose.test.yml up
rm docker-compose.test.yml

# Test integration endpoints
echo "Testing service integration..."

# Test PhotoPrism API
if ! curl -sf "http://localhost:2342/api/v1/status" > /dev/null; then
    echo "Error: PhotoPrism API not responding"
    exit 1
fi

# Test Redis connection
if ! docker exec photoprism2-redis-1 redis-cli ping > /dev/null; then
    echo "Error: Redis connection failed"
    exit 1
fi

# Test Database connection
if ! docker exec photoprism2-mariadb-1 mysqladmin ping -h localhost > /dev/null; then
    echo "Error: Database connection failed"
    exit 1
fi

# Test model availability
for model in facenet nasnet nsfw places365 yolov4; do
    if [ ! -d "./storage/models/$model" ]; then
        echo "Error: Required model $model not found"
        exit 1
    fi
done

# Test required ports are available
for port in 2342 6379 3306; do
    if lsof -i:$port > /dev/null; then
        echo "Error: Port $port is already in use"
        exit 1
    fi
done

# Verify storage directories
for dir in storage originals import database; do
    if [ ! -d "./$dir" ]; then
        echo "Creating directory: $dir"
        mkdir -p "./$dir"
    fi
done

echo "Docker system check completed successfully"
