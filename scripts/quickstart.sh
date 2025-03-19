#!/bin/bash

# Display welcome banner
cat << "EOF"
 ____  _           _        ____       _               ____
|  _ \| |__   ___ | |_ ___ |  _ \ _ __(_)___ _ __ ___ |___ \
| |_) | '_ \ / _ \| __/ _ \| |_) | '__| / __| '_ ` _ \  __) |
|  __/| | | | (_) | || (_) |  __/| |  | \__ \ | | | | |/ __/
|_|   |_| |_|\___/ \__\___/|_|   |_|  |_|___/_| |_| |_|_____|

Docker Setup Wizard
EOF

echo -e "\nThis script will guide you through the PhotoPrism2 setup process.\n"

# Check Docker installation
echo "Checking Docker installation..."
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
else
    echo "✅ Docker is installed"
    docker --version
fi

if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is not installed. Please install Docker Compose first."
    exit 1
else
    echo "✅ Docker Compose is installed"
    docker-compose --version
fi

# Setup environment
echo -e "\nPreparing environment..."
bash ./scripts/setup-docker-env.sh

# Check network connectivity
echo -e "\nChecking Docker network connectivity..."
bash ./scripts/docker-network-check.sh

# Authenticate with Docker Hub if needed
echo -e "\nWould you like to authenticate with Docker Hub? (recommended to avoid rate limits) [y/N]"
read -r use_auth
if [[ "$use_auth" =~ ^[Yy]$ ]]; then
    bash ./scripts/docker-login-helper.sh
fi

# Build the Docker image
echo -e "\nBuilding Docker image..."
bash ./scripts/build-with-retry.sh

# Start with docker-compose
if [ $? -eq 0 ]; then
    echo -e "\nWould you like to start the services now? [Y/n]"
    read -r start_now
    if [[ ! "$start_now" =~ ^[Nn]$ ]]; then
        echo "Starting services with docker-compose..."
        docker-compose up -d

        if [ $? -eq 0 ]; then
            echo -e "\n✅ PhotoPrism2 is now starting!"
            echo "You can access it at: http://localhost:${PHOTOPRISM_PORT:-2342}"
            echo "Admin username: admin"
            echo "Admin password: $(cat ./docker/secrets/photoprism_admin_password.txt)"
            echo -e "\nTo view logs: docker-compose logs -f"
            echo "To stop: docker-compose down"
        else
            echo "❌ Failed to start services. Check the logs for more information."
        fi
    else
        echo "Skipping service start. You can start manually with: docker-compose up -d"
    fi
else
    echo "❌ Docker build failed. Please check the logs for more information."
fi
