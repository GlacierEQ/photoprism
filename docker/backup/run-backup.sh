#!/bin/bash
# Automated backup script for PhotoPrism

# Exit on error
set -e

# Configuration
BACKUP_DIR="/backup"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/photoprism-backup-${TIMESTAMP}.tar.gz"
LOG_FILE="${BACKUP_DIR}/logs/backup-${TIMESTAMP}.log"
MAX_BACKUPS=7  # Keep last 7 backups

# Create logs directory if it doesn't exist
mkdir -p "${BACKUP_DIR}/logs"

# Log function
log() {
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1" | tee -a "$LOG_FILE"
}

log "Starting PhotoPrism backup"

# Create temporary directory
TEMP_DIR=$(mktemp -d)
log "Created temporary directory: $TEMP_DIR"

# Backup database
log "Backing up database..."
mysqldump -h mariadb -u photoprism -p$MYSQL_PASSWORD --single-transaction --databases photoprism > "$TEMP_DIR/database.sql"

# Create metadata file
log "Creating backup metadata..."
cat > "$TEMP_DIR/metadata.json" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "backup_type": "automated"
}
EOF

# Create archive
log "Creating backup archive..."
tar -czf "$BACKUP_FILE" -C "$TEMP_DIR" .
log "Backup archive created: $BACKUP_FILE"

# Calculate checksum
sha256sum "$BACKUP_FILE" > "${BACKUP_FILE}.sha256"
log "Created SHA256 checksum"

# Clean up
rm -rf "$TEMP_DIR"
log "Cleaned up temporary files"

# Manage retention policy
log "Managing retention policy (keeping last $MAX_BACKUPS backups)"
ls -t "${BACKUP_DIR}"/photoprism-backup-*.tar.gz | tail -n +$((MAX_BACKUPS + 1)) | xargs rm -f 2>/dev/null || true
ls -t "${BACKUP_DIR}"/photoprism-backup-*.sha256 | tail -n +$((MAX_BACKUPS + 1)) | xargs rm -f 2>/dev/null || true

# Get backup size
BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
log "Backup completed successfully. Size: $BACKUP_SIZE"
