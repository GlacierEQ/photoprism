#!/bin/bash
set -e

# PhotoPrism Production Deployment Script
# ---------------------------------------

# Configuration
DOCKER_COMPOSE_FILE="docker/docker-compose.prod.yml"
ENV_FILE="docker/.env.prod"

# Print colored output
print_green() {
    echo -e "\e[32m$1\e[0m"
}

print_yellow() {
    echo -e "\e[33m$1\e[0m"
}

print_blue() {
    echo -e "\e[34m$1\e[0m"
}

# Header
print_blue "========================================="
print_blue " PhotoPrism Production Deployment Script "
print_blue "========================================="
echo ""

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    print_yellow "Docker not found. Please install Docker first."
    exit 1
fi

# Check if Docker Compose is installed
if ! command -v docker compose &> /dev/null && ! command -v docker-compose &> /dev/null; then
    print_yellow "Docker Compose not found. Please install Docker Compose first."
    exit 1
fi

# Determine docker compose command
if command -v docker compose &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
else
    DOCKER_COMPOSE="docker-compose"
fi

# Check if environment file exists
if [ ! -f "$ENV_FILE" ]; then
    print_yellow "Environment file $ENV_FILE not found. Creating from example..."
    cp docker/.env.example "$ENV_FILE" 2>/dev/null || cp docker/.env "$ENV_FILE" 2>/dev/null || touch "$ENV_FILE"
    print_yellow "Please edit $ENV_FILE with your settings before continuing."
    print_yellow "Press Enter to continue or Ctrl+C to abort..."
    read -r
fi

# Create required directories
print_green "Creating required directories..."
mkdir -p storage originals import database backups redis

# Pull Docker images
print_green "Pulling latest Docker images..."
$DOCKER_COMPOSE -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" pull

# Stop any existing containers
print_green "Stopping any existing containers..."
$DOCKER_COMPOSE -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" down --remove-orphans 2>/dev/null || true

# Start containers
print_green "Starting PhotoPrism containers..."
$DOCKER_COMPOSE -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" up -d

# Wait a bit for services to start
sleep 5

# Verify deployment
print_green "Verifying deployment..."
if $DOCKER_COMPOSE -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" ps | grep -q "photoprism.*Up"; then
    print_green "✓ PhotoPrism started successfully"
else
    print_yellow "⚠ PhotoPrism container may not have started properly. Checking logs:"
    $DOCKER_COMPOSE -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" logs photoprism
fi

if $DOCKER_COMPOSE -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" ps | grep -q "photoprism_brains.*Up"; then
    print_green "✓ BRAINS service started successfully"
else
    print_yellow "⚠ BRAINS service may not have started properly. Checking logs:"
    $DOCKER_COMPOSE -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" logs brains
fi

# Extract site URL from environment
SITE_URL=$(grep PHOTOPRISM_SITE_URL "$ENV_FILE" | cut -d '=' -f2 || echo "http://localhost:2342")
ADMIN_USER=$(grep PHOTOPRISM_ADMIN_USER "$ENV_FILE" | cut -d '=' -f2 || echo "admin")

echo ""
print_blue "🎉 PhotoPrism deployment complete!"
print_blue "📷 Access your photo library at: $SITE_URL"
print_blue "👤 Username: $ADMIN_USER"
print_blue "🔑 Password: (as specified in $ENV_FILE)"
echo ""

print_yellow "Useful commands:"
print_yellow "  View logs: $DOCKER_COMPOSE -f $DOCKER_COMPOSE_FILE --env-file $ENV_FILE logs -f"
print_yellow "  Stop services: $DOCKER_COMPOSE -f $DOCKER_COMPOSE_FILE --env-file $ENV_FILE down"
print_yellow "  Restart services: $DOCKER_COMPOSE -f $DOCKER_COMPOSE_FILE --env-file $ENV_FILE restart"
echo ""

# Make this script executable
chmod +x "$0"
