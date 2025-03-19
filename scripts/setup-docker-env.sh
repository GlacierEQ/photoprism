#!/bin/bash

PROJECT_ROOT=$(pwd)
LOG_DIR="${PROJECT_ROOT}/logs"
DATA_DIR="${PROJECT_ROOT}/data"
SECRETS_DIR="${PROJECT_ROOT}/docker/secrets"
CONFIG_DIR="${PROJECT_ROOT}/docker/config"

# Setup directories
echo "Creating required directories..."
mkdir -p ${LOG_DIR}
mkdir -p ${DATA_DIR}/{photos,thumbnails,storage,mysql,postgres,letsencrypt,brains-models,import,grafana,prometheus}
mkdir -p ${SECRETS_DIR}
mkdir -p ${CONFIG_DIR}/{mariadb,postgres}
mkdir -p ${PROJECT_ROOT}/backups

# Create empty config files if they don't exist
if [ ! -f ${CONFIG_DIR}/mariadb/custom.cnf ]; then
  echo "# MariaDB custom configuration" > ${CONFIG_DIR}/mariadb/custom.cnf
  echo "[mysqld]" >> ${CONFIG_DIR}/mariadb/custom.cnf
  echo "# Add your custom settings here" >> ${CONFIG_DIR}/mariadb/custom.cnf
fi

if [ ! -f ${CONFIG_DIR}/postgres/init.sql ]; then
  echo "-- PostgreSQL initialization script" > ${CONFIG_DIR}/postgres/init.sql
  echo "-- Will be executed on first start" >> ${CONFIG_DIR}/postgres/init.sql
fi

# Create secret files with random passwords if they don't exist
if [ ! -f ${SECRETS_DIR}/photoprism_admin_password.txt ]; then
  echo "Creating random admin password..."
  openssl rand -base64 12 > ${SECRETS_DIR}/photoprism_admin_password.txt
fi

if [ ! -f ${SECRETS_DIR}/photoprism_db_password.txt ]; then
  echo "Creating random database password..."
  openssl rand -base64 12 > ${SECRETS_DIR}/photoprism_db_password.txt
fi

if [ ! -f ${SECRETS_DIR}/mariadb_root_password.txt ]; then
  echo "Creating random MariaDB root password..."
  openssl rand -base64 16 > ${SECRETS_DIR}/mariadb_root_password.txt
fi

echo "Environment setup complete!"
echo "Generated passwords:"
echo "PhotoPrism Admin: $(cat ${SECRETS_DIR}/photoprism_admin_password.txt)"
echo "PhotoPrism Database: $(cat ${SECRETS_DIR}/photoprism_db_password.txt)"
echo "MariaDB Root: $(cat ${SECRETS_DIR}/mariadb_root_password.txt)"
echo ""
echo "Make sure to save these passwords securely!"
echo "You can now run: ./scripts/build-with-retry.sh"
