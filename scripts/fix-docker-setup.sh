#!/bin/bash

# Script to fix common Docker setup issues
echo "PhotoPrism2 Docker Setup Repair Tool"
echo "===================================="

# Check if Docker is running
echo "Checking Docker daemon status..."
if ! docker info &> /dev/null; then
  echo "❌ Docker daemon is not running!"
  echo "Please start Docker Desktop or Docker service and try again."
  exit 1
else
  echo "✅ Docker daemon is running"
fi

# Fix Docker Compose file conflicts
echo -e "\nFixing Docker Compose file conflicts..."
if [ -f "compose.yaml" ]; then
  echo "- Removing obsolete compose.yaml"
  rm compose.yaml
fi

if [ -f "docker-compose.override.yml" ]; then
  echo "- Updating docker-compose.override.yml format"
  # Remove version line if present
  sed -i '/^version:/d' docker-compose.override.yml
fi

# Check if Docker Desktop is using Windows or Linux containers
echo -e "\nChecking Docker engine type..."
if docker info | grep -q "windows"; then
  echo "⚠️ Docker is running in Windows container mode!"
  echo "Please switch to Linux containers in Docker Desktop settings."
fi

# Check network connectivity to Docker Hub
echo -e "\nChecking Docker Hub connectivity..."
if ! curl -s --connect-timeout 5 https://registry-1.docker.io/v2/ > /dev/null; then
  echo "❌ Cannot connect to Docker Hub!"
  echo "Please check your network connection or proxy settings."
else
  echo "✅ Docker Hub is reachable"
fi

# Resolve Docker pipe issues (common on Windows)
echo -e "\nChecking for Docker pipe issues..."
if [ "$(uname -s)" = "MINGW"* ] || [ "$(uname -s)" = "MSYS"* ]; then
  echo "- Running on Windows Git Bash/MSYS"
  echo "- Ensuring Docker context is set to desktop-linux"
  docker context use desktop-linux &> /dev/null || echo "⚠️ Could not set Docker context"
fi

# Ensure required directories exist
echo -e "\nChecking required directories..."
mkdir -p docker/secrets
mkdir -p docker/config/mariadb
mkdir -p docker/config/postgres
mkdir -p docker/traefik
mkdir -p data/mysql
mkdir -p data/storage

# Generate missing secret files
echo -e "\nChecking for required secret files..."
if [ ! -f "docker/secrets/photoprism_admin_password.txt" ]; then
  echo "- Creating admin password file"
  echo "admin" > docker/secrets/photoprism_admin_password.txt
fi

if [ ! -f "docker/secrets/photoprism_db_password.txt" ]; then
  echo "- Creating database password file"
  echo "photoprism" > docker/secrets/photoprism_db_password.txt
fi

if [ ! -f "docker/secrets/mariadb_root_password.txt" ]; then
  echo "- Creating MariaDB root password file"
  echo "root" > docker/secrets/mariadb_root_password.txt
fi

echo -e "\nVerifying Docker images..."
echo "- Pulling Traefik image"
docker pull traefik:v2.10 || echo "⚠️ Failed to pull Traefik image"

echo "- Pulling MariaDB image"
docker pull mariadb:10.11 || echo "⚠️ Failed to pull MariaDB image"

# Make scripts executable
chmod +x scripts/fix-docker-setup.sh
chmod +x scripts/docker-build.sh

echo -e "\n✅ Setup repair completed!"
echo -e "\nYou can now try running again with:"
echo "docker-compose up -d"
echo -e "\nFor building custom images, use the docker-build.sh script:"
echo "./scripts/docker-build.sh --tag custom"
echo -e "\nIf you continue to have issues, try restarting Docker Desktop"
echo "or refer to the Docker Desktop troubleshooting documentation."
