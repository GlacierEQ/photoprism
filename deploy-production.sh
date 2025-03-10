#!/bin/bash
set -e

# PhotoPrism Production Deployment Script
# ---------------------------------------
# This script automates the deployment of PhotoPrism in production.
# It handles Docker image updates, database backups, and configuration.

# Default configuration
DOCKER_COMPOSE_FILE="docker/docker-compose.prod.yml"
ENV_FILE="docker/.env.prod"
BACKUP_DIR="storage/backup/$(date +%Y%m%d_%H%M%S)"
LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"

# Function to log messages
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to validate environment
validate_environment() {
  log "Validating environment..."

  # Check if the script is run as root or with sudo
  if [[ $EUID -ne 0 ]]; then
    log "ERROR: This script must be run as root or with sudo."
    exit 1
  fi
  
  # Check if Docker is installed
  if ! command -v docker &> /dev/null; then
    log "ERROR: Docker not found. Please install Docker first."
    exit 1
  fi
  
  # Check if Docker Compose is installed
  if ! command -v docker compose &> /dev/null; then
    log "ERROR: Docker Compose not found. Please install Docker Compose first."
    exit 1
  fi
  
  # Check if environment file exists
  if [ ! -f "$ENV_FILE" ]; then
    log "WARNING: Environment file $ENV_FILE not found. Creating from example..."
    cp docker/.env.example "$ENV_FILE"
  fi

  log "Environment validation complete."
}

# Function to create backup
create_backup() {
  log "Creating backups before deployment..."
  mkdir -p "$BACKUP_DIR"
  
  # Backup database if container is running
  if docker compose -f "$DOCKER_COMPOSE_FILE" ps | grep -q db; then
    log "Backing up database..."
    docker compose -f "$DOCKER_COMPOSE_FILE" exec -T db mysqldump -u photoprism -p"${MYSQL_PASSWORD}" photoprism > "$BACKUP_DIR/database.sql"
  else
    log "Database container not running, skipping database backup"
  fi
  
  # Backup configuration
  log "Backing up configuration..."
  cp "$ENV_FILE" "$BACKUP_DIR/.env.backup"
  cp "$DOCKER_COMPOSE_FILE" "$BACKUP_DIR/docker-compose.backup.yml"
  
  log "Backups completed and stored in $BACKUP_DIR"
}

# Function to pull latest images
pull_images() {
  log "Pulling latest Docker images..."
  docker compose -f "$DOCKER_COMPOSE_FILE" pull
  log "Images pulled successfully."
}

# Function to update brain models
update_brain_models() {
  log "Updating brain models..."
  ./scripts/download-brains.sh
  log "Brain models updated successfully."
}

# Function to build Docker image
build_image() {
  log "Building Docker image..."
  
  # Default values
  DOCKERFILE_PATH="./Dockerfile"
  CONTEXT_PATH="./"
  IMAGE_NAME="photoprism:latest"
  NO_CACHE="true"
  
  # Check if arguments are provided through environment variables
  if [ -n "$DOCKERFILE_PATH" ]; then
    DOCKERFILE_PATH="$DOCKERFILE_PATH"
  fi
  if [ -n "$CONTEXT_PATH" ]; then
    CONTEXT_PATH="$CONTEXT_PATH"
  fi
  if [ -n "$IMAGE_NAME" ]; then
    IMAGE_NAME="$IMAGE_NAME"
  fi
  
  # Build command
  BUILD_COMMAND="docker build"
  
  # Add --no-cache if specified
  if [ "$NO_CACHE" = "true" ]; then
    BUILD_COMMAND="$BUILD_COMMAND --no-cache"
  fi
  
  BUILD_COMMAND="$BUILD_COMMAND -t $IMAGE_NAME -f $DOCKERFILE_PATH $CONTEXT_PATH"
  
  log "Executing build command: $BUILD_COMMAND"
  
  # Execute build command
  eval "$BUILD_COMMAND"
  
  if [ $? -ne 0 ]; then
    log "ERROR: Docker image build failed."
    exit 1
  fi
  
  log "Docker image built successfully."
}

# Function to initialize the database
initialize_database() {
  log "Initializing database..."

  # Default values
  DB_DRIVER="mysql"
  DB_HOST="localhost"
  DB_PORT="3306"
  DB_NAME="photoprism"
  DB_USER="photoprism"
  DB_PASSWORD="your_secure_password"

  # Override defaults with environment variables if set
  if [ -n "$DB_DRIVER" ]; then
    DB_DRIVER="$DB_DRIVER"
  fi
  if [ -n "$DB_HOST" ]; then
    DB_HOST="$DB_HOST"
  fi
  if [ -n "$DB_PORT" ]; then
    DB_PORT="$DB_PORT"
  fi
  if [ -n "$DB_NAME" ]; then
    DB_NAME="$DB_NAME"
  fi
  if [ -n "$DB_USER" ]; then
    DB_USER="$DB_USER"
  fi
  if [ -n "$DB_PASSWORD" ]; then
    DB_PASSWORD="$DB_PASSWORD"
  fi

  # Check if the database exists
  DB_EXIST_CHECK=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW DATABASES LIKE '$DB_NAME'" | grep "$DB_NAME")

  if [ -z "$DB_EXIST_CHECK" ]; then
    log "Database '$DB_NAME' does not exist. Creating..."

    # Create the database, user, and grant permissions
    mysql -h "$DB_HOST" -P "$DB_PORT" -u root -p"${MYSQL_ROOT_PASSWORD}" <<EOF
CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'%';
FLUSH PRIVILEGES;
EOF

    log "Database '$DB_NAME' created and user '$DB_USER' configured."
  else
    log "Database '$DB_NAME' already exists. Skipping creation."
  fi

  log "Database initialization complete."
}

# Function to configure authentication
configure_authentication() {
  log "Configuring authentication..."

  # Default values
  AUTH_MODE="password"
  ADMIN_USER="admin"
  ADMIN_PASSWORD="photoprism"

  # Override defaults with environment variables if set
  if [ -n "$AUTH_MODE" ]; then
    AUTH_MODE="$AUTH_MODE"
  fi
  if [ -n "$ADMIN_USER" ]; then
    ADMIN_USER="$ADMIN_USER"
  fi
  if [ -n "$ADMIN_PASSWORD" ]; then
    ADMIN_PASSWORD="$ADMIN_PASSWORD"
  fi

  # Set admin user and password in .env file
  log "Setting admin user and password in $ENV_FILE..."
  
  # Check if PHOTOPRISM_ADMIN_USER exists, if not, add it
  if ! grep -q "^PHOTOPRISM_ADMIN_USER=" "$ENV_FILE"; then
    echo "PHOTOPRISM_ADMIN_USER=$ADMIN_USER" >> "$ENV_FILE"
  else
    # If it exists, update it
    sed -i "s/^PHOTOPRISM_ADMIN_USER=.*/PHOTOPRISM_ADMIN_USER=$ADMIN_USER/" "$ENV_FILE"
  fi
  
  # Check if PHOTOPRISM_ADMIN_PASSWORD exists, if not, add it
  if ! grep -q "^PHOTOPRISM_ADMIN_PASSWORD=" "$ENV_FILE"; then
    echo "PHOTOPRISM_ADMIN_PASSWORD=$ADMIN_PASSWORD" >> "$ENV_FILE"
  else
    # If it exists, update it
    sed -i "s/^PHOTOPRISM_ADMIN_PASSWORD=.*/PHOTOPRISM_ADMIN_PASSWORD=$ADMIN_PASSWORD/" "$ENV_FILE"
  fi

  log "Admin user and password set in $ENV_FILE."
  log "Authentication configuration complete."
}

# Function to configure storage paths
configure_storage() {
  log "Configuring storage paths..."

  # Default values
  ASSETS_PATH="/photoprism/assets"
  STORAGE_PATH="/photoprism/storage"
  ORIGINALS_PATH="/photoprism/storage/originals"
  IMPORT_PATH="/photoprism/storage/import"
  DISABLE_BACKUPS="false"

  # Override defaults with environment variables if set
  if [ -n "$ASSETS_PATH" ]; then
    ASSETS_PATH="$ASSETS_PATH"
  fi
  if [ -n "$STORAGE_PATH" ]; then
    STORAGE_PATH="$STORAGE_PATH"
  fi
  if [ -n "$ORIGINALS_PATH" ]; then
    ORIGINALS_PATH="$ORIGINALS_PATH"
  fi
  if [ -n "$IMPORT_PATH" ]; then
    IMPORT_PATH="$IMPORT_PATH"
  fi
  if [ -n "$DISABLE_BACKUPS" ]; then
    DISABLE_BACKUPS="$DISABLE_BACKUPS"
  fi

  # Set storage paths in .env file
  log "Setting storage paths in $ENV_FILE..."
  
  # Check if PHOTOPRISM_ASSETS_PATH exists, if not, add it
  if ! grep -q "^PHOTOPRISM_ASSETS_PATH=" "$ENV_FILE"; then
    echo "PHOTOPRISM_ASSETS_PATH=$ASSETS_PATH" >> "$ENV_FILE"
  else
    # If it exists, update it
    sed -i "s/^PHOTOPRISM_ASSETS_PATH=.*/PHOTOPRISM_ASSETS_PATH=$ASSETS_PATH/" "$ENV_FILE"
  fi
  
  # Check if PHOTOPRISM_STORAGE_PATH exists, if not, add it
  if ! grep -q "^PHOTOPRISM_STORAGE_PATH=" "$ENV_FILE"; then
    echo "PHOTOPRISM_STORAGE_PATH=$STORAGE_PATH" >> "$ENV_FILE"
  else
    # If it exists, update it
    sed -i "s/^PHOTOPRISM_STORAGE_PATH=.*/PHOTOPRISM_STORAGE_PATH=$STORAGE_PATH/" "$ENV_FILE"
  fi
  
  # Check if PHOTOPRISM_ORIGINALS_PATH exists, if not, add it
  if ! grep -q "^PHOTOPRISM_ORIGINALS_PATH=" "$ENV_FILE"; then
    echo "PHOTOPRISM_ORIGINALS_PATH=$ORIGINALS_PATH" >> "$ENV_FILE"
  else
    # If it exists, update it
    sed -i "s/^PHOTOPRISM_ORIGINALS_PATH=.*/PHOTOPRISM_ORIGINALS_PATH=$ORIGINALS_PATH/" "$ENV_FILE"
  fi
  
  # Check if PHOTOPRISM_IMPORT_PATH exists, if not, add it
  if ! grep -q "^PHOTOPRISM_IMPORT_PATH=" "$ENV_FILE"; then
    echo "PHOTOPRISM_IMPORT_PATH=$IMPORT_PATH" >> "$ENV_FILE"
  else
    # If it exists, update it
    sed -i "s/^PHOTOPRISM_IMPORT_PATH=.*/PHOTOPRISM_IMPORT_PATH=$IMPORT_PATH/" "$ENV_FILE"
  fi
  
  # Check if PHOTOPRISM_DISABLE_BACKUPS exists, if not, add it
  if ! grep -q "^PHOTOPRISM_DISABLE_BACKUPS=" "$ENV_FILE"; then
    echo "PHOTOPRISM_DISABLE_BACKUPS=$DISABLE_BACKUPS" >> "$ENV_FILE"
  else
    # If it exists, update it
    sed -i "s/^PHOTOPRISM_DISABLE_BACKUPS=.*/PHOTOPRISM_DISABLE_BACKUPS=$DISABLE_BACKUPS/" "$ENV_FILE"
  fi

  log "Storage paths set in $ENV_FILE."
  log "Storage configuration complete."
}

# Function to configure web interface
configure_web_interface() {
  log "Configuring web interface..."

  # Default values
  SITE_URL="https://app.localssl.dev/"
  SITE_CAPTION="AI-Powered Photos App"
  SITE_DESCRIPTION="Tags and finds pictures automatically!"
  SITE_AUTHOR="@photoprism_app"
  DISABLE_PLACES="false"
  READ_ONLY="false"

  # Override defaults with environment variables if set
  if [ -n "$SITE_URL" ]; then
    SITE_URL="$SITE_URL"
  fi
  if [ -n "$SITE_CAPTION" ]; then
    SITE_CAPTION="$SITE_CAPTION"
  fi
  if [ -n "$SITE_DESCRIPTION" ]; then
    SITE_DESCRIPTION="$SITE_DESCRIPTION"
  fi
  if [ -n "$SITE_AUTHOR" ]; then
    SITE_AUTHOR="$SITE_AUTHOR"
  fi
  if [ -n "$DISABLE_PLACES" ]; then
    DISABLE_PLACES="$DISABLE_PLACES"
  fi
  if [ -n "$READ_ONLY" ]; then
    READ_ONLY="$READ_ONLY"
  fi

  # Set web interface settings in .env file
  log "Setting web interface settings in $ENV_FILE..."
  
  # Check if PHOTOPRISM_SITE_URL exists, if not, add it
  if ! grep -q "^PHOTOPRISM_SITE_URL=" "$ENV_FILE"; then
    echo "PHOTOPRISM_SITE_URL=$SITE_URL" >> "$ENV_FILE"
  else
    # If it exists, update it
    sed -i "s/^PHOTOPRISM_SITE_URL=.*/PHOTOPRISM_SITE_URL=$SITE_URL/" "$ENV_FILE"
  fi
  
  # Check if PHOTOPRISM_SITE_CAPTION exists, if not, add it
  if ! grep -q "^PHOTOPRISM_SITE_CAPTION=" "$ENV_FILE"; then
    echo "PHOTOPRISM_SITE_CAPTION=\"$SITE_CAPTION\"" >> "$ENV_FILE"
  else
    # If it exists, update it
    sed -i "s/^PHOTOPRISM_SITE_CAPTION=.*/PHOTOPRISM_SITE_CAPTION=\"$SITE_CAPTION\"/" "$ENV_FILE"
  fi
  
  # Check if PHOTOPRISM_SITE_DESCRIPTION exists, if not, add it
  if ! grep -q "^PHOTOPRISM_SITE_DESCRIPTION=" "$ENV_FILE"; then
    echo "PHOTOPRISM_SITE_DESCRIPTION=\"$SITE_DESCRIPTION\"" >> "$ENV_FILE"
  else
    # If it exists, update it
    sed -i "s/^PHOTOPRISM_SITE_DESCRIPTION=.*/PHOTOPRISM_SITE_DESCRIPTION=\"$SITE_DESCRIPTION\"/" "$ENV_FILE"
  fi
  
  # Check if PHOTOPRISM_SITE_AUTHOR exists, if not, add it
  if ! grep -q "^PHOTOPRISM_SITE_AUTHOR=" "$ENV_FILE"; then
    echo "PHOTOPRISM_SITE_AUTHOR=$SITE_AUTHOR" >> "$ENV_FILE"
  else
    # If it exists, update it
    sed -i "s/^PHOTOPRISM_SITE_AUTHOR=.*/PHOTOPRISM_SITE_AUTHOR=$SITE_AUTHOR/" "$ENV_FILE"
  fi
  
  # Check if PHOTOPRISM_DISABLE_PLACES exists, if not, add it
  if ! grep -q "^PHOTOPRISM_DISABLE_PLACES=" "$ENV_FILE"; then
    echo "PHOTOPRISM_DISABLE_PLACES=$DISABLE_PLACES" >> "$ENV_FILE"
  else
    # If it exists, update it
    sed -i "s/^PHOTOPRISM_DISABLE_PLACES=.*/PHOTOPRISM_DISABLE_PLACES=$DISABLE_PLACES/" "$ENV_FILE"
  fi
  
  # Check if PHOTOPRISM_READ_ONLY exists, if not, add it
  if ! grep -q "^PHOTOPRISM_READ_ONLY=" "$ENV_FILE"; then
    echo "PHOTOPRISM_READ_ONLY=$READ_ONLY" >> "$ENV_FILE"
  else
    # If it exists, update it
    sed -i "s/^PHOTOPRISM_READ_ONLY=.*/PHOTOPRISM_READ_ONLY=$READ_ONLY/" "$ENV_FILE"
  fi

  log "Web interface settings set in $ENV_FILE."
  log "Web interface configuration complete."
}

# Function to configure performance settings
configure_performance() {
  log "Configuring performance settings..."

  # Default values
  HTTP_MODE="release"
  DEBUG="false"
  THUMB_LIBRARY="auto"
  THUMB_FILTER="lanczos"
  THUMB_UNCACHED="true"
  THUMB_SIZE="1920"
  JPEG_SIZE="7680"

  # Override defaults with environment variables if set
  if [ -n "$HTTP_MODE" ]; then
    HTTP_MODE="$HTTP_MODE"
  fi
  if [ -n "$DEBUG" ]; then
    DEBUG="$DEBUG"
  fi
  if [ -n "$THUMB_LIBRARY" ]; then
    THUMB_LIBRARY="$THUMB_LIBRARY"
  fi
  if [ -n "$THUMB_FILTER" ]; then
    THUMB_FILTER="$THUMB_FILTER"
  fi
  if [ -n "$THUMB_UNCACHED" ]; then
    THUMB_UNCACHED="$THUMB_UNCACHED"
  fi
  if [ -n "$THUMB_SIZE" ]; then
    THUMB_SIZE="$THUMB_SIZE"
  fi
  if [ -n "$JPEG_SIZE" ]; then
    JPEG_SIZE="$JPEG_SIZE"
  fi

  # Set performance settings in .env file
  log "Setting performance configuration in $ENV_FILE..."
  
  # HTTP mode
  if ! grep -q "^PHOTOPRISM_HTTP_MODE=" "$ENV_FILE"; then
    echo "PHOTOPRISM_HTTP_MODE=$HTTP_MODE" >> "$ENV_FILE"
  else
    sed -i "s/^PHOTOPRISM_HTTP_MODE=.*/PHOTOPRISM_HTTP_MODE=$HTTP_MODE/" "$ENV_FILE"
  fi
  
  # Debug mode
  if ! grep -q "^PHOTOPRISM_DEBUG=" "$ENV_FILE"; then
    echo "PHOTOPRISM_DEBUG=$DEBUG" >> "$ENV_FILE"
  else
    sed -i "s/^PHOTOPRISM_DEBUG=.*/PHOTOPRISM_DEBUG=$DEBUG/" "$ENV_FILE"
  fi
  
  # Thumbnail library
  if ! grep -q "^PHOTOPRISM_THUMB_LIBRARY=" "$ENV_FILE"; then
    echo "PHOTOPRISM_THUMB_LIBRARY=$THUMB_LIBRARY" >> "$ENV_FILE"
  else
    sed -i "s/^PHOTOPRISM_THUMB_LIBRARY=.*/PHOTOPRISM_THUMB_LIBRARY=$THUMB_LIBRARY/" "$ENV_FILE"
  fi
  
  # Thumbnail filter
  if ! grep -q "^PHOTOPRISM_THUMB_FILTER=" "$ENV_FILE"; then
    echo "PHOTOPRISM_THUMB_FILTER=$THUMB_FILTER" >> "$ENV_FILE"
  else
    sed -i "s/^PHOTOPRISM_THUMB_FILTER=.*/PHOTOPRISM_THUMB_FILTER=$THUMB_FILTER/" "$ENV_FILE"
  fi
  
  # Uncached thumbnails
  if ! grep -q "^PHOTOPRISM_THUMB_UNCACHED=" "$ENV_FILE"; then
    echo "PHOTOPRISM_THUMB_UNCACHED=$THUMB_UNCACHED" >> "$ENV_FILE"
  else
    sed -i "s/^PHOTOPRISM_THUMB_UNCACHED=.*/PHOTOPRISM_THUMB_UNCACHED=$THUMB_UNCACHED/" "$ENV_FILE"
  fi
  
  # Thumbnail size
  if ! grep -q "^PHOTOPRISM_THUMB_SIZE=" "$ENV_FILE"; then
    echo "PHOTOPRISM_THUMB_SIZE=$THUMB_SIZE" >> "$ENV_FILE"
  else
    sed -i "s/^PHOTOPRISM_THUMB_SIZE=.*/PHOTOPRISM_THUMB_SIZE=$THUMB_SIZE/" "$ENV_FILE"
  fi
  
  # JPEG size
  if ! grep -q "^PHOTOPRISM_JPEG_SIZE=" "$ENV_FILE"; then
    echo "PHOTOPRISM_JPEG_SIZE=$JPEG_SIZE" >> "$ENV_FILE"
  else
    sed -i "s/^PHOTOPRISM_JPEG_SIZE=.*/PHOTOPRISM_JPEG_SIZE=$JPEG_SIZE/" "$ENV_FILE"
  fi

  log "Performance settings configured in $ENV_FILE."
}

# Function to configure video transcoding settings
configure_video_transcoding() {
  log "Configuring video transcoding settings..."

  # Default values
  FFMPEG_ENCODER="software"
  FFMPEG_SIZE="3840"
  FFMPEG_BITRATE="50"
  LIBVA_DRIVER_NAME="i965"

  # Override defaults with environment variables if set
  if [ -n "$FFMPEG_ENCODER" ]; then
    FFMPEG_ENCODER="$FFMPEG_ENCODER"
  fi
  if [ -n "$FFMPEG_SIZE" ]; then
    FFMPEG_SIZE="$FFMPEG_SIZE"
  fi
  if [ -n "$FFMPEG_BITRATE" ]; then
    FFMPEG_BITRATE="$FFMPEG_BITRATE"
  fi
  if [ -n "$LIBVA_DRIVER_NAME" ]; then
    LIBVA_DRIVER_NAME="$LIBVA_DRIVER_NAME"
  fi

  # Set video transcoding settings in .env file
  log "Setting video transcoding configuration in $ENV_FILE..."
  
  # FFmpeg encoder
  if ! grep -q "^PHOTOPRISM_FFMPEG_ENCODER=" "$ENV_FILE"; then
    echo "PHOTOPRISM_FFMPEG_ENCODER=$FFMPEG_ENCODER" >> "$ENV_FILE"
  else
    sed -i "s/^PHOTOPRISM_FFMPEG_ENCODER=.*/PHOTOPRISM_FFMPEG_ENCODER=$FFMPEG_ENCODER/" "$ENV_FILE"
  fi
  
  # FFmpeg size
  if ! grep -q "^PHOTOPRISM_FFMPEG_SIZE=" "$ENV_FILE"; then
    echo "PHOTOPRISM_FFMPEG_SIZE=$FFMPEG_SIZE" >> "$ENV_FILE"
  else
    sed -i "s/^PHOTOPRISM_FFMPEG_SIZE=.*/PHOTOPRISM_FFMPEG_SIZE=$FFMPEG_SIZE/" "$ENV_FILE"
  fi
  
  # FFmpeg bitrate
  if ! grep -q "^PHOTOPRISM_FFMPEG_BITRATE=" "$ENV_FILE"; then
    echo "PHOTOPRISM_FFMPEG_BITRATE=$FFMPEG_BITRATE" >> "$ENV_FILE"
  else
    sed -i "s/^PHOTOPRISM_FFMPEG_BITRATE=.*/PHOTOPRISM_FFMPEG_BITRATE=$FFMPEG_BITRATE/" "$ENV_FILE"
  fi
  
  # LibVA driver name
  if ! grep -q "^LIBVA_DRIVER_NAME=" "$ENV_FILE"; then
    echo "LIBVA_DRIVER_NAME=$LIBVA_DRIVER_NAME" >> "$ENV_FILE"
  else
    sed -i "s/^LIBVA_DRIVER_NAME=.*/LIBVA_DRIVER_NAME=$LIBVA_DRIVER_NAME/" "$ENV_FILE"
  fi

  log "Video transcoding settings configured in $ENV_FILE."
}

# Function to deploy application
deploy_app() {
  log "Deploying PhotoPrism production environment..."
  
  # Stop current containers if running
  if docker compose -f "$DOCKER_COMPOSE_FILE" ps | grep -q Up; then
    log "Stopping current containers..."
    docker compose -f "$DOCKER_COMPOSE_FILE" down --remove-orphans
  fi
  
  # Start new containers
  log "Starting new containers..."
  docker compose -f "$DOCKER_COMPOSE_FILE" up -d
  
  # Check if containers started successfully
  if docker compose -f "$DOCKER_COMPOSE_FILE" ps | grep -q Exit; then
    log "ERROR: Some containers failed to start. Check the logs for details."
    docker compose -f "$DOCKER_COMPOSE_FILE" logs
    exit 1
  fi
  
  log "Deployment completed successfully."
}

# Function to verify deployment
verify_deployment() {
  log "Verifying deployment..."
  
  # Wait for services to initialize
  log "Waiting for services to initialize (30s)..."
  sleep 30
  
  # Check if PhotoPrism is responding
  PHOTOPRISM_URL=$(grep "PHOTOPRISM_SITE_URL" "$ENV_FILE" | cut -d '=' -f2)
  if [ -z "$PHOTOPRISM_URL" ]; then
    PHOTOPRISM_URL="http://localhost:2342"
  fi
  
  log "Testing connection to PhotoPrism at $PHOTOPRISM_URL..."
  if curl -s -o /dev/null -w "%{http_code}" "$PHOTOPRISM_URL" | grep -q "200\|302\|401"; then
    log "PhotoPrism is up and running!"
  else
    log "WARNING: PhotoPrism may not be fully initialized yet. Check the logs."
    docker compose -f "$DOCKER_COMPOSE_FILE" logs photoprism
  fi
  
  # Verify brain service
  log "Checking brain service..."
  if docker compose -f "$DOCKER_COMPOSE_FILE" ps | grep -q "brains.*Up"; then
    log "Brain service is running."
  else
    log "WARNING: Brain service may not be running. Check the logs."
    docker compose -f "$DOCKER_COMPOSE_FILE" logs brains
  fi
  
  log "Deployment verification completed."
}

# Function to finalize installation
finalize_installation() {
  log "Finalizing installation..."

  # Default values
  MIGRATE_DATABASE="true"
  START_SERVICES="true"
  RUN_INDEXING="true"

  # Override defaults with environment variables if set
  if [ -n "$MIGRATE_DATABASE" ]; then
    MIGRATE_DATABASE="$MIGRATE_DATABASE"
  fi
  if [ -n "$START_SERVICES" ]; then
    START_SERVICES="$START_SERVICES"
  fi
  if [ -n "$RUN_INDEXING" ]; then
    RUN_INDEXING="$RUN_INDEXING"
  fi

  # Get the container name for PhotoPrism
  PHOTOPRISM_CONTAINER=$(docker compose -f "$DOCKER_COMPOSE_FILE" ps -q photoprism)
  
  if [ -z "$PHOTOPRISM_CONTAINER" ]; then
    log "ERROR: PhotoPrism container not found. Cannot finalize installation."
    exit 1
  fi

  # Migrate database if required
  if [ "$MIGRATE_DATABASE" = "true" ]; then
    log "Running database migration..."
    docker exec $PHOTOPRISM_CONTAINER photoprism migrations up
    
    if [ $? -ne 0 ]; then
      log "WARNING: Database migration encountered issues."
    else
      log "Database migration completed successfully."
    fi
  else
    log "Skipping database migration as per configuration."
  fi

  # Start services if required
  if [ "$START_SERVICES" = "true" ]; then
    log "Starting PhotoPrism services..."
    docker exec $PHOTOPRISM_CONTAINER photoprism start
    
    if [ $? -ne 0 ]; then
      log "ERROR: Failed to start PhotoPrism services."
      exit 1
    else
      log "PhotoPrism services started successfully."
    fi
  else
    log "Skipping service startup as per configuration."
  fi

  # Run indexing if required
  if [ "$RUN_INDEXING" = "true" ]; then
    log "Starting initial indexing of photos. This may take some time depending on your library size..."
    docker exec $PHOTOPRISM_CONTAINER photoprism index
    
    if [ $? -ne 0 ]; then
      log "WARNING: Indexing process encountered issues."
    else
      log "Initial indexing completed successfully."
    fi
  else
    log "Skipping initial indexing as per configuration."
  fi

  log "Installation finalized."
}

# Main execution
main() {
  log "Starting PhotoPrism production deployment..."

  # Initialize variables from .env file
  if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
  fi

  validate_environment
  create_backup
  initialize_database # Initialize the database
  build_image # Build the Docker image
  configure_authentication # Configure authentication
  configure_storage # Configure storage paths
  configure_web_interface # Configure web interface settings
  configure_performance # Configure performance settings
  configure_video_transcoding # Configure video transcoding settings
  pull_images
  update_brain_models
  deploy_app
  verify_deployment
  finalize_installation # Finalize the installation
  log "Deployment process completed. Check logs for any warnings or errors."
}

main "$@"
