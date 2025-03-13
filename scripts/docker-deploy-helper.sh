#!/bin/bash
# Docker deployment helper functions

# Configuration
CONFIG_DIR="docker/config"
ENV_FILE=".env"
COMPOSE_FILE="docker-compose.yml"
STACK_FILE="docker/docker-stack.yml"
OVERRIDE_FILE="docker-compose.override.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check if Docker is running
check_docker() {
    if ! docker info &> /dev/null; then
        echo -e "${RED}Error: Docker is not running!${NC}"
        echo "Please start Docker and try again."
        exit 1
    fi
}

# Load environment variables
load_env() {
    if [ -f "$ENV_FILE" ]; then
        export $(grep -v '^#' "$ENV_FILE" | xargs)
    else
        echo -e "${YELLOW}Warning: $ENV_FILE not found, using default values.${NC}"
    fi
}

# Check if secrets exist, generate if needed
check_secrets() {
    local secrets_dir="docker/secrets"
    mkdir -p "$secrets_dir"

    local files=(
        "photoprism_admin_password.txt"
        "photoprism_db_password.txt"
        "mariadb_root_password.txt"
    )

    for file in "${files[@]}"; do
        if [ ! -f "$secrets_dir/$file" ]; then
            echo -e "${YELLOW}Generating secret file: $file${NC}"
            # Generate random password
            openssl rand -base64 24 | tr -d '\n' > "$secrets_dir/$file"
            chmod 600 "$secrets_dir/$file"
        fi
    done
}

# Create required directories
create_directories() {
    echo -e "${BLUE}Creating required directories...${NC}"
    mkdir -p data/storage data/originals data/import data/mysql data/brains-models
}

# Validate compose file
validate_compose() {
    echo -e "${BLUE}Validating Docker Compose configuration...${NC}"
    docker compose -f "$COMPOSE_FILE" config --quiet
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Compose file validation successful.${NC}"
    else
        echo -e "${RED}Compose file validation failed!${NC}"
        exit 1
    fi

    # If override exists, validate the combined configuration
    if [ -f "$OVERRIDE_FILE" ]; then
        echo -e "${BLUE}Validating with override file...${NC}"
        docker compose -f "$COMPOSE_FILE" -f "$OVERRIDE_FILE" config --quiet
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Combined compose configuration is valid.${NC}"
        else
            echo -e "${RED}Combined compose configuration is invalid!${NC}"
            exit 1
        fi
    fi
}

# Pull latest images
pull_images() {
    echo -e "${BLUE}Pulling latest Docker images...${NC}"
    if [ -f "$OVERRIDE_FILE" ]; then
        docker compose -f "$COMPOSE_FILE" -f "$OVERRIDE_FILE" pull
    else
        docker compose -f "$COMPOSE_FILE" pull
    fi
}

# Deploy to Docker Compose
deploy_compose() {
    echo -e "${BLUE}Deploying with Docker Compose...${NC}"
    if [ -f "$OVERRIDE_FILE" ]; then
        docker compose -f "$COMPOSE_FILE" -f "$OVERRIDE_FILE" up -d
    else
        docker compose -f "$COMPOSE_FILE" up -d
    fi

    echo -e "${GREEN}Deployment complete!${NC}"
}

# Deploy to Docker Swarm
deploy_swarm() {
    echo -e "${BLUE}Deploying to Docker Swarm...${NC}"

    # Check if swarm is initialized
    if ! docker info | grep -q "Swarm: active"; then
        echo -e "${YELLOW}Swarm not active. Initializing swarm...${NC}"
        docker swarm init --advertise-addr $(hostname -i) || true
    fi

    # Create secrets in Docker
    echo -e "${BLUE}Creating Docker secrets...${NC}"
    create_docker_secrets

    # Deploy the stack
    echo -e "${BLUE}Deploying stack...${NC}"
    docker stack deploy -c "$STACK_FILE" photoprism

    echo -e "${GREEN}Swarm deployment complete!${NC}"
}

# Create Docker secrets for swarm mode
create_docker_secrets() {
    local secrets_dir="docker/secrets"

    # Remove existing secrets
    docker secret ls --format "{{.Name}}" | grep -E "photoprism_|mariadb_" | xargs -r docker secret rm

    # Create new secrets
    for secret_file in "$secrets_dir"/*.txt; do
        local secret_name=$(basename "$secret_file" .txt)
        cat "$secret_file" | docker secret create "$secret_name" -
    done
}

# Check the deployment status
check_status() {
    echo -e "${BLUE}Checking deployment status...${NC}"

    # Check if in swarm mode
    if docker info | grep -q "Swarm: active" && docker stack ls | grep -q "photoprism"; then
        echo -e "${GREEN}Services running in swarm mode:${NC}"
        docker stack services photoprism
    else
        echo -e "${GREEN}Services running in compose mode:${NC}"
        docker compose -f "$COMPOSE_FILE" ps
    fi

    # Check if PhotoPrism is responding
    local url="${PHOTOPRISM_SITE_URL:-http://localhost:2342}"
    echo -e "${BLUE}Checking PhotoPrism availability at $url...${NC}"

    if command -v curl &> /dev/null; then
        if curl -s -o /dev/null -w "%{http_code}" "$url" | grep -q "200\|302\|401"; then
            echo -e "${GREEN}PhotoPrism is responding!${NC}"
        else
            echo -e "${RED}PhotoPrism is not responding properly.${NC}"
            echo "Check logs with: docker compose -f $COMPOSE_FILE logs photoprism"
        fi
    else
        echo -e "${YELLOW}curl not found. Please check PhotoPrism manually at $url${NC}"
    fi
}

# View logs
view_logs() {
    local service=$1

    # If no service specified, default to photoprism
    if [ -z "$service" ]; then
        service="photoprism"
    fi

    # Check if in swarm mode
    if docker info | grep -q "Swarm: active" && docker stack ls | grep -q "photoprism"; then
        echo -e "${BLUE}Viewing logs for $service in swarm mode...${NC}"
        docker service logs "photoprism_${service}" -f
    else
        echo -e "${BLUE}Viewing logs for $service in compose mode...${NC}"
        docker compose -f "$COMPOSE_FILE" logs "$service" -f
    fi
}

# Create database backup
backup_database() {
    local backup_dir="backups"
    local timestamp=$(date +"%Y%m%d-%H%M%S")
    local backup_file="${backup_dir}/photoprism-db-${timestamp}.sql"

    mkdir -p "$backup_dir"

    echo -e "${BLUE}Creating database backup...${NC}"

    # Check if in swarm mode
    if docker info | grep -q "Swarm: active" && docker stack ls | grep -q "photoprism"; then
        echo -e "${YELLOW}Swarm mode detected. Manual backup required.${NC}"
        echo "Run: docker exec <mariadb-container> mysqldump -u photoprism -p<password> photoprism > $backup_file"
    else
        # Get database password from env file or secrets
        local db_password=""
        if [ -f "docker/secrets/photoprism_db_password.txt" ]; then
            db_password=$(cat docker/secrets/photoprism_db_password.txt)
        elif [ -n "$PHOTOPRISM_DATABASE_PASSWORD" ]; then
            db_password=$PHOTOPRISM_DATABASE_PASSWORD
        else
            echo -e "${RED}Database password not found!${NC}"
            exit 1
        fi

        # Create backup
        docker compose -f "$COMPOSE_FILE" exec -T mariadb \
            mysqldump -u photoprism -p"$db_password" photoprism > "$backup_file"

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Database backup created: $backup_file${NC}"
        else
            echo -e "${RED}Database backup failed!${NC}"
        fi
    fi
}
