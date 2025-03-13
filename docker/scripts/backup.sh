#!/bin/bash
# PhotoPrism Backup Script
# Automates backup of PhotoPrism data including database and files

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${PROJECT_DIR}/.env"
COMPOSE_FILE="${PROJECT_DIR}/docker/compose/production.yml"
BACKUP_DIR="${PROJECT_DIR}/docker/backup"
BACKUP_NAME=${1:-"photoprism-backup-$(date +"%Y%m%d-%H%M%S")"}
BACKUP_FILE="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
LOG_FILE="${PROJECT_DIR}/docker/logs/backup-$(date +"%Y%m%d-%H%M%S").log"

# Create backup directory if it doesn't exist
mkdir -p "${BACKUP_DIR}"
mkdir -p "${PROJECT_DIR}/docker/logs"

# Load environment variables
if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
fi

# Log function
log() {
  local msg="[$(date +"%Y-%m-%d %H:%M:%S")] $1"
  echo "$msg" | tee -a "$LOG_FILE"
}

# Error handling
handle_error() {
  log "ERROR: Backup failed at line $1"
  log "See log file at $LOG_FILE for details"
  exit 1
}

trap 'handle_error $LINENO' ERR

# Check if PhotoPrism is running
check_running() {
  log "Checking if PhotoPrism services are running..."

  if ! docker compose -f "$COMPOSE_FILE" ps | grep -q "mariadb"; then
    log "PhotoPrism services are not running. Starting only MariaDB for backup..."
    docker compose -f "$COMPOSE_FILE" up -d mariadb
    sleep 10
  fi

  log "Services check completed."
}

# Create temporary directory for backup
create_temp_dir() {
  log "Creating temporary directory for backup..."
  TEMP_BACKUP_DIR=$(mktemp -d)
  mkdir -p "${TEMP_BACKUP_DIR}/database"
  mkdir -p "${TEMP_BACKUP_DIR}/originals"
  mkdir -p "${TEMP_BACKUP_DIR}/storage"
  mkdir -p "${TEMP_BACKUP_DIR}/config"
  log "Temporary directory created at ${TEMP_BACKUP_DIR}"
}

# Backup database
backup_database() {
  log "Backing up database..."

  # Get database credentials from environment
  local DB_USER=${MYSQL_USER:-"photoprism"}
  local DB_PASS=${PHOTOPRISM_DATABASE_PASSWORD}
  local DB_NAME=${MYSQL_DATABASE:-"photoprism"}

  # Export database
  docker compose -f "$COMPOSE_FILE" exec -T mariadb mysqldump \
    --single-transaction \
    --quick \
    --lock-tables=false \
    -u root \
    -p"${MYSQL_ROOT_PASSWORD}" \
    "${DB_NAME}" > "${TEMP_BACKUP_DIR}/database/photoprism.sql"

  log "Database backup completed."
}

# Backup important files
backup_files() {
  log "Backing up configuration files..."

  # Get data path from environment
  local DATA_PATH=${PHOTOPRISM_DATA_PATH:-"${PROJECT_DIR}/data"}

  # Copy .env file
  cp "$ENV_FILE" "${TEMP_BACKUP_DIR}/config/.env"

  # Create backup info file
  cat > "${TEMP_BACKUP_DIR}/backup-info.json" << EOF
{
  "name": "${BACKUP_NAME}",
  "timestamp": "$(date +"%Y-%m-%d %H:%M:%S")",
  "hostname": "$(hostname)",
  "photoprism_version": "$(docker compose -f "$COMPOSE_FILE" exec -T photoprism photoprism -v 2>/dev/null || echo "unknown")"
}
EOF

  log "Configuration backup completed."
}

# Create backup archive
create_archive() {
  log "Creating backup archive..."

  # Create tar.gz archive
  tar -czf "${BACKUP_FILE}" -C "${TEMP_BACKUP_DIR}" .

  # Calculate checksum
  sha256sum "${BACKUP_FILE}" > "${BACKUP_FILE}.sha256"

  log "Backup archive created at ${BACKUP_FILE}"
  log "Backup size: $(du -h "${BACKUP_FILE}" | cut -f1)"
}

# Cleanup temporary files
cleanup() {
  log "Cleaning up temporary files..."

  if [ -d "${TEMP_BACKUP_DIR}" ]; then
    rm -rf "${TEMP_BACKUP_DIR}"
  fi

  log "Cleanup completed."
}

# Manage backup retention
manage_retention() {
  log "Managing backup retention..."

  local MAX_BACKUPS=${BACKUP_RETENTION_COUNT:-7}

  # Count existing backups
  local BACKUPS_COUNT=$(ls -1 "${BACKUP_DIR}"/*.tar.gz 2>/dev/null | wc -l)

  if [ "$BACKUPS_COUNT" -gt "$MAX_BACKUPS" ]; then
    log "Found ${BACKUPS_COUNT} backups, keeping ${MAX_BACKUPS} most recent."
    ls -t "${BACKUP_DIR}"/*.tar.gz | tail -n +$((MAX_BACKUPS + 1)) | xargs rm -f
    ls -t "${BACKUP_DIR}"/*.sha256 | tail -n +$((MAX_BACKUPS + 1)) | xargs rm -f
  fi

  log "Backup retention managed."
}

# Main execution
main() {
  log "==================== PHOTOPRISM BACKUP ===================="
  log "Starting backup process: ${BACKUP_NAME}"

  check_running
  create_temp_dir
  backup_database
  backup_files
  create_archive
  manage_retention
  cleanup

  log "==================== BACKUP COMPLETE ===================="
  log "Backup successfully created at: ${BACKUP_FILE}"
}

# Execute main function
main
