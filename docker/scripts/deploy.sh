#!/bin/bash
# PhotoPrism Docker Deployment Script
# Handles the deployment of PhotoPrism in Docker environments

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="${PROJECT_DIR}/.env"
COMPOSE_FILE="${PROJECT_DIR}/docker-compose.yml"
OVERRIDE_FILE="${PROJECT_DIR}/docker-compose.override.yml"
STACK_FILE="${PROJECT_DIR}/docker/docker-stack.yml"
LOG_FILE="${PROJECT_DIR}/logs/deploy-$(date +"%Y%m%d-%H%M%S").log"
DEPLOYMENT_MODE="${DEPLOYMENT_MODE:-compose}"  # compose or swarm
BACKUP_BEFORE_DEPLOY="${BACKUP_BEFORE_DEPLOY:-true}"

# Create logs directory
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Error handler
handle_error() {
    local line_number="$1"
    local exit_code="$2"
    log "ERROR" "Deployment failed at line $line_number with code $exit_code"
    exit "$exit_code"
}

trap 'handle_error ${LINENO} $?' ERR

# Check Docker is running
check_docker() {
    log "INFO" "Checking Docker status..."
    if ! docker info &>/dev/null; then
        log "ERROR" "Docker is not running! Please start Docker and try again."
        exit 1
    fi
    log "INFO" "Docker is running properly."
}

# Load environment variables
load_env() {
    log "INFO" "Loading environment variables..."
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
        log "INFO" "Loaded environment from $ENV_FILE"
    else
        log "WARN" "Environment file not found at $ENV_FILE. Using default values."
    fi
}

# Validate configuration
validate_config() {
    log "INFO" "Validating deployment configuration..."

    # Check for required files
    if [ "$DEPLOYMENT_MODE" = "compose" ] && [ ! -f "$COMPOSE_FILE" ]; then
        log "ERROR" "Compose file not found at $COMPOSE_FILE"
        exit 1
    fi

    if [ "$DEPLOYMENT_MODE" = "swarm" ] && [ ! -f "$STACK_FILE" ]; then
        log "ERROR" "Stack file not found at $STACK_FILE"
        exit 1
    fi

    # Create required directories
    mkdir -p "${PROJECT_DIR}/data/storage"
    mkdir -p "${PROJECT_DIR}/data/originals"
    mkdir -p "${PROJECT_DIR}/data/import"
    mkdir -p "${PROJECT_DIR}/data/mysql"

    # Ensure secrets directory exists
    mkdir -p "${PROJECT_DIR}/docker/secrets"

    # Check and create secrets
    check_secrets

    log "INFO" "Configuration validated successfully."
}

# Check and create Docker secrets
check_secrets() {
    log "INFO" "Checking Docker secrets..."
    local secrets_dir="${PROJECT_DIR}/docker/secrets"

    # Create required secret files if they don't exist
    if [ ! -f "${secrets_dir}/photoprism_admin_password.txt" ]; then
        log "WARN" "Admin password secret not found, creating from environment variable or default..."
        echo "${PHOTOPRISM_ADMIN_PASSWORD:-change-me-now}" > "${secrets_dir}/photoprism_admin_password.txt"
        chmod 600 "${secrets_dir}/photoprism_admin_password.txt"
    fi

    if [ ! -f "${secrets_dir}/photoprism_db_password.txt" ]; then
        log "WARN" "Database password secret not found, creating from environment variable or default..."
        echo "${PHOTOPRISM_DATABASE_PASSWORD:-change-me-now-db}" > "${secrets_dir}/photoprism_db_password.txt"
        chmod 600 "${secrets_dir}/photoprism_db_password.txt"
    fi

    if [ ! -f "${secrets_dir}/mariadb_root_password.txt" ]; then
        log "WARN" "MariaDB root password secret not found, creating from environment variable or default..."
        echo "${MYSQL_ROOT_PASSWORD:-change-me-now-root}" > "${secrets_dir}/mariadb_root_password.txt"
        chmod 600 "${secrets_dir}/mariadb_root_password.txt"
    fi

    log "INFO" "Secrets checked and created if needed."
}

# Create a backup before deployment
create_backup() {
    if [ "$BACKUP_BEFORE_DEPLOY" = "true" ]; then
        log "INFO" "Creating backup before deployment..."

        BACKUP_DIR="${PROJECT_DIR}/backups"
        mkdir -p "$BACKUP_DIR"

        # Check if database container is running
        if docker compose -f "$COMPOSE_FILE" ps | grep -q "mariadb"; then
            local timestamp=$(date +"%Y%m%d-%H%M%S")
            local backup_file="${BACKUP_DIR}/pre-deploy-backup-${timestamp}.sql"

            log "INFO" "Backing up database to $backup_file..."

            # Get database password
            local db_password=""
            if [ -f "${PROJECT_DIR}/docker/secrets/photoprism_db_password.txt" ]; then
                db_password=$(cat "${PROJECT_DIR}/docker/secrets/photoprism_db_password.txt")
            elif [ -n "$PHOTOPRISM_DATABASE_PASSWORD" ]; then
                db_password="$PHOTOPRISM_DATABASE_PASSWORD"
            else
                log "WARN" "Could not find database password, skipping database backup."
                return
            fi

            # Execute backup
            docker compose -f "$COMPOSE_FILE" exec -T mariadb \
                mysqldump -u photoprism -p"$db_password" photoprism > "$backup_file"

            if [ $? -eq 0 ]; then
                log "INFO" "Database backup created successfully at $backup_file"
            else
                log "WARN" "Database backup failed."
            fi
        else
            log "WARN" "MariaDB container not running, skipping database backup."
        fi
    else
        log "INFO" "Backup before deployment is disabled."
    fi
}

# Pull latest images
pull_images() {
    log "INFO" "Pulling latest Docker images..."

    if [ "$DEPLOYMENT_MODE" = "compose" ]; then
        if [ -f "$OVERRIDE_FILE" ]; then
            docker compose -f "$COMPOSE_FILE" -f "$OVERRIDE_FILE" pull
        else
            docker compose -f "$COMPOSE_FILE" pull
        fi
    else
        log "INFO" "In swarm mode, images will be pulled during deployment."
    fi

    log "INFO" "Docker images pulled successfully."
}

# Deploy using Docker Compose
deploy_with_compose() {
    log "INFO" "Deploying with Docker Compose..."

    # Stop existing services
    if docker compose -f "$COMPOSE_FILE" ps | grep -q "Up"; then
        log "INFO" "Stopping existing services..."
        docker compose -f "$COMPOSE_FILE" stop
    fi

    # Start services
    log "INFO" "Starting services..."
    if [ -f "$OVERRIDE_FILE" ]; then
        docker compose -f "$COMPOSE_FILE" -f "$OVERRIDE_FILE" up -d
    else
        docker compose -f "$COMPOSE_FILE" up -d
    fi

    log "INFO" "Services started. Waiting for initialization..."
    sleep 10

    # Check service status
    log "INFO" "Checking service status..."
    docker compose -f "$COMPOSE_FILE" ps

    log "INFO" "Docker Compose deployment completed successfully."
}

# Deploy using Docker Swarm
deploy_with_swarm() {
    log "INFO" "Deploying with Docker Swarm..."

    # Check if swarm is initialized
    if ! docker info | grep -q "Swarm: active"; then
        log "WARN" "Docker Swarm is not initialized. Initializing now..."
        docker swarm init --advertise-addr $(hostname -i) || true
    fi

    # Create Docker secrets for swarm
    log "INFO" "Creating Docker secrets for swarm..."
    for secret_file in "${PROJECT_DIR}/docker/secrets"/*.txt; do
        secret_name=$(basename "$secret_file" .txt)

        # Check if secret already exists
        if docker secret ls | grep -q "$secret_name"; then
            log "INFO" "Secret $secret_name already exists, removing..."
            docker secret rm "$secret_name" || true
        fi

        # Create new secret
        log "INFO" "Creating secret $secret_name..."
        cat "$secret_file" | docker secret create "$secret_name" -
    done

    # Deploy the stack
    log "INFO" "Deploying stack..."
    docker stack deploy -c "$STACK_FILE" photoprism

    log "INFO" "Docker Swarm deployment initiated. Checking service status..."
    sleep 10
    docker stack services photoprism

    log "INFO" "Docker Swarm deployment completed successfully."
}

# Wait for services to be ready
wait_for_services() {
    log "INFO" "Waiting for services to be ready..."

    # Maximum wait time in seconds
    local max_wait=60
    local elapsed=0
    local ready=false

    while [ $elapsed -lt $max_wait ] && [ "$ready" = "false" ]; do
        if [ "$DEPLOYMENT_MODE" = "compose" ]; then
            # Check if PhotoPrism is responding
            if curl -s -o /dev/null -w "%{http_code}" http://localhost:2342/ | grep -q "200\|401\|302"; then
                log "INFO" "PhotoPrism is responding."
                ready=true
            else
                log "INFO" "Waiting for PhotoPrism to become ready... ($elapsed/$max_wait seconds)"
                sleep 5
                elapsed=$((elapsed + 5))
            fi
        else
            # In swarm mode, just check if services are running
            if docker stack services photoprism | grep -q "1/1"; then
                log "INFO" "PhotoPrism services are running."
                ready=true
            else
                log "INFO" "Waiting for PhotoPrism services to start... ($elapsed/$max_wait seconds)"
                sleep 5
                elapsed=$((elapsed + 5))
            fi
        fi
    done

    if [ "$ready" = "true" ]; then
        log "INFO" "Services are ready."
    else
        log "WARN" "Services may not be fully ready after waiting $max_wait seconds."
    fi
}

# Perform post-deployment checks
post_deployment_checks() {
    log "INFO" "Performing post-deployment checks..."

    # Check container health
    if [ "$DEPLOYMENT_MODE" = "compose" ]; then
        log "INFO" "Checking container health..."
        docker compose -f "$COMPOSE_FILE" ps
    else
        log "INFO" "Checking service health..."
        docker stack services photoprism
    fi

    # Log access information
    local site_url="${PHOTOPRISM_SITE_URL:-http://localhost:2342/}"
    log "INFO" "PhotoPrism is accessible at: $site_url"
    log "INFO" "Default login: ${PHOTOPRISM_ADMIN_USER:-admin} / [password from secrets or environment]"

    log "INFO" "Post-deployment checks completed."
}

# Show completion message
show_completion() {
    log "INFO" "Deployment completed successfully!"

    cat << EOF

╔════════════════════════════════════════════════════════════════╗
║                 PHOTOPRISM DEPLOYMENT COMPLETE                 ║
╠════════════════════════════════════════════════════════════════╣
║                                                                ║
║  Your PhotoPrism instance is now running.                      ║
║                                                                ║
║  Access URL: ${PHOTOPRISM_SITE_URL:-http://localhost:2342/}                    ║
║  Username:   ${PHOTOPRISM_ADMIN_USER:-admin}                                        ║
║  Password:   [stored in secrets or environment]                ║
║                                                                ║
║  Deployment log: $LOG_FILE                    ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
EOF
}

# Main function
main() {
    log "INFO" "Starting PhotoPrism deployment process..."
    check_docker
    load_env
    validate_config
    create_backup
    pull_images

    if [ "$DEPLOYMENT_MODE" = "compose" ]; then
        deploy_with_compose
    else
        deploy_with_swarm
    fi

    wait_for_services
    post_deployment_checks
    show_completion

    log "INFO" "Deployment script completed."
}

# Run the main function
main
