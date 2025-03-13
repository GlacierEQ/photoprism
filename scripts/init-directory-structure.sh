#!/bin/bash
# Initialize the full directory structure for PhotoPrism with recursive organization

set -e

# Base directories
BASE_DIR="data"
CONFIG_DIR="docker/config"
SCRIPT_DIR="scripts"
SECRETS_DIR="docker/secrets"
MONITORING_DIR="docker/monitoring"
NGINX_DIR="docker/nginx"
TRAEFIK_DIR="docker/traefik"
BACKUP_DIR="docker/backup"
TOOLS_DIR="tools"

# Create data directories with properly nested structure
mkdir -p "${BASE_DIR}/storage/cache"
mkdir -p "${BASE_DIR}/storage/sidecar"
mkdir -p "${BASE_DIR}/storage/config"
mkdir -p "${BASE_DIR}/storage/albums"
mkdir -p "${BASE_DIR}/storage/backups"
mkdir -p "${BASE_DIR}/storage/logs"
mkdir -p "${BASE_DIR}/originals"
mkdir -p "${BASE_DIR}/import"
mkdir -p "${BASE_DIR}/brains-models/faces"
mkdir -p "${BASE_DIR}/brains-models/objects"
mkdir -p "${BASE_DIR}/brains-models/scenes"
mkdir -p "${BASE_DIR}/brains-models/nsfw"
mkdir -p "${BASE_DIR}/mysql"

# Create configuration directories
mkdir -p "${CONFIG_DIR}/mariadb"
mkdir -p "${CONFIG_DIR}/photoprism"
mkdir -p "${CONFIG_DIR}/settings"

# Create monitoring directories
mkdir -p "${MONITORING_DIR}/prometheus"
mkdir -p "${MONITORING_DIR}/grafana/provisioning/dashboards"
mkdir -p "${MONITORING_DIR}/grafana/provisioning/datasources"
mkdir -p "${MONITORING_DIR}/loki"

# Create proxy directories
mkdir -p "${NGINX_DIR}/conf.d"
mkdir -p "${NGINX_DIR}/ssl"
mkdir -p "${TRAEFIK_DIR}/dynamic"

# Create backup directories
mkdir -p "${BACKUP_DIR}/scripts"
mkdir -p "${BACKUP_DIR}/logs"

# Create secrets directory (with restricted permissions)
mkdir -p "${SECRETS_DIR}"
chmod 700 "${SECRETS_DIR}"

# Create example secret files if they don't exist
if [ ! -f "${SECRETS_DIR}/photoprism_admin_password.txt" ]; then
    echo "change-me-now" > "${SECRETS_DIR}/photoprism_admin_password.txt"
    chmod 600 "${SECRETS_DIR}/photoprism_admin_password.txt"
fi

if [ ! -f "${SECRETS_DIR}/photoprism_db_password.txt" ]; then
    echo "change-me-now-db" > "${SECRETS_DIR}/photoprism_db_password.txt"
    chmod 600 "${SECRETS_DIR}/photoprism_db_password.txt"
fi

if [ ! -f "${SECRETS_DIR}/mariadb_root_password.txt" ]; then
    echo "change-me-now-root" > "${SECRETS_DIR}/mariadb_root_password.txt"
    chmod 600 "${SECRETS_DIR}/mariadb_root_password.txt"
fi

# Copy default config files if they don't exist
if [ ! -f "${CONFIG_DIR}/settings.json" ]; then
    cp "${CONFIG_DIR}/settings.json.example" "${CONFIG_DIR}/settings.json" 2>/dev/null || echo "No settings example found"
fi

echo "Directory structure initialized successfully"
echo "Remember to set proper passwords in ${SECRETS_DIR}/*.txt files"
