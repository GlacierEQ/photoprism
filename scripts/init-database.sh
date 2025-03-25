#!/bin/bash
set -e

# Configuration
DB_HOST=${DB_HOST:-"mariadb"}
DB_PORT=${DB_PORT:-3306}
DB_NAME=${MYSQL_DATABASE:-"photoprism"}
DB_USER=${MYSQL_USER:-"photoprism"}
MAX_RETRIES=30
RETRY_INTERVAL=2

# Function to check database connection
check_db_connection() {
    mysqladmin ping -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"${MYSQL_PASSWORD}" >/dev/null 2>&1
}

# Wait for database to be ready
echo "Waiting for database connection..."
for ((i=1; i<=MAX_RETRIES; i++)); do
    if check_db_connection; then
        echo "Database connection established"
        break
    fi

    if [ $i -eq $MAX_RETRIES ]; then
        echo "Failed to connect to database after $MAX_RETRIES attempts"
        exit 1
    fi

    echo "Attempt $i of $MAX_RETRIES: Database not ready, waiting..."
    sleep $RETRY_INTERVAL
done

# Initialize database
echo "Initializing database..."
mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"${MYSQL_PASSWORD}" "$DB_NAME" << 'EOF'
-- Create required tables if they don't exist
CREATE TABLE IF NOT EXISTS migrations (
    id INT AUTO_INCREMENT PRIMARY KEY,
    version VARCHAR(255) NOT NULL,
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
EOF

echo "Database initialization complete"
