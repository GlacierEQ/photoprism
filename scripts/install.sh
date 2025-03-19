#!/bin/bash

# PhotoPrism2 Docker Installation and Setup Script
# This script provides commands for installation and configuration

# Set strict error handling
set -e
set -o pipefail

# Configuration variables (can be overridden via environment variables)
DOCKER_COMPOSE_VERSION=${DOCKER_COMPOSE_VERSION:-"v2.24.5"}
LOG_DIR=${LOG_DIR:-"./logs"}
INSTALL_DIR=$(pwd)

# Create log directory
mkdir -p "$LOG_DIR"
LOGFILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"

# Log function
log() {
  local msg="[$(date +"%Y-%m-%d %H:%M:%S")] $1"
  echo "$msg" | tee -a "$LOGFILE"
}

# Error handler
handle_error() {
  log "ERROR: Installation failed at line $1"
  exit 1
}

# Set error trap
trap 'handle_error $LINENO' ERR

# Check operating system
log "Detecting operating system..."
OS="$(uname -s)"
case "$OS" in
  Linux)
    log "Linux detected"
    INSTALL_TYPE="linux"
    ;;
  Darwin)
    log "macOS detected"
    INSTALL_TYPE="macos"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    log "Windows detected"
    INSTALL_TYPE="windows"
    ;;
  *)
    log "Unsupported operating system: $OS"
    exit 1
    ;;
esac

# Display welcome message
echo "===========================================" | tee -a "$LOGFILE"
echo "     PhotoPrism2 Docker Installation       " | tee -a "$LOGFILE"
echo "===========================================" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# Function for Linux installation
install_linux() {
  log "Starting Linux installation process..."

  # Update package lists
  log "Updating package lists..."
  sudo apt-get update

  # Install required packages
  log "Installing prerequisites..."
  sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

  # Add Docker's official GPG key
  log "Adding Docker repository key..."
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

  # Set up stable repository
  log "Setting up Docker repository..."
  echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  # Install Docker Engine
  log "Installing Docker Engine..."
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io

  # Add user to docker group
  log "Adding current user to docker group..."
  sudo usermod -aG docker $USER

  # Install Docker Compose
  log "Installing Docker Compose..."
  sudo curl -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose

  log "Starting Docker service..."
  sudo systemctl enable docker
  sudo systemctl start docker
}

# Function for macOS installation
install_macos() {
  log "Starting macOS installation process..."

  # Check if Homebrew is installed
  if ! command -v brew &> /dev/null; then
    log "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    log "Homebrew already installed, updating..."
    brew update
  fi

  # Install Docker Desktop
  log "Installing Docker Desktop via Homebrew..."
  brew install --cask docker

  log "Starting Docker Desktop..."
  open -a Docker

  # Wait for Docker to start
  log "Waiting for Docker to start..."
  until docker info &> /dev/null; do
    echo -n "."
    sleep 2
  done
  echo ""

  log "Docker Desktop installation complete."
  log "Please ensure Docker has enough resources allocated (Settings > Resources)"
}

# Function for Windows installation
install_windows() {
  log "Starting Windows installation process..."

  log "For Windows, please install Docker Desktop manually:"
  log "1. Download Docker Desktop from: https://www.docker.com/products/docker-desktop"
  log "2. Install Docker Desktop and launch it"
  log "3. Ensure WSL2 is enabled"
  log "4. In Docker Desktop settings:"
  log "   - Ensure 'Use the WSL2 based engine' is selected"
  log "   - Give Docker at least 4GB of RAM in Resources > Advanced"
  log ""
  log "After installation, run this script again to continue setup."

  read -p "Have you installed Docker Desktop? (y/n): " docker_installed
  if [[ $docker_installed =~ ^[Nn]$ ]]; then
    log "Please install Docker Desktop first and run this script again."
    exit 0
  fi
}

# Function to verify Docker installation
verify_docker() {
  log "Verifying Docker installation..."

  if ! command -v docker &> /dev/null; then
    log "Docker command not found. Installation may have failed."
    exit 1
  fi

  if ! docker info &> /dev/null; then
    log "Docker daemon is not running."
    log "Please start Docker and run this script again."
    exit 1
  fi

  log "Docker is installed and running correctly."
  docker version
}

# Function to configure PhotoPrism environment
configure_photoprism() {
  log "Configuring PhotoPrism2 environment..."

  # Ensure required directories exist
  log "Creating required directories..."
  mkdir -p docker/secrets
  mkdir -p docker/config/mariadb
  mkdir -p docker/config/postgres
  mkdir -p docker/traefik
  mkdir -p data/mysql
  mkdir -p data/storage

  # Generate initial configuration files
  log "Generating configuration files..."

  # Create secret files if they don't exist
  if [ ! -f "docker/secrets/photoprism_admin_password.txt" ]; then
    log "Setting up admin password..."
    read -sp "Enter admin password (default: admin): " admin_pwd
    echo ${admin_pwd:-admin} > docker/secrets/photoprism_admin_password.txt
    echo ""
  fi

  if [ ! -f "docker/secrets/photoprism_db_password.txt" ]; then
    log "Setting up database password..."
    read -sp "Enter database password (default: photoprism): " db_pwd
    echo ${db_pwd:-photoprism} > docker/secrets/photoprism_db_password.txt
    echo ""
  fi

  if [ ! -f "docker/secrets/mariadb_root_password.txt" ]; then
    log "Setting up MariaDB root password..."
    read -sp "Enter MariaDB root password (default: root): " mariadb_pwd
    echo ${mariadb_pwd:-root} > docker/secrets/mariadb_root_password.txt
    echo ""
  fi

  # Make scripts executable
  log "Making scripts executable..."
  chmod +x scripts/*.sh

  # Fix Docker setup
  log "Running Docker setup fix script..."
  ./scripts/fix-docker-setup.sh
}

# Function to pull required images
pull_images() {
  log "Pulling required Docker images..."

  docker pull traefik:v2.10 || log "⚠️ Failed to pull Traefik image"
  docker pull mariadb:10.11 || log "⚠️ Failed to pull MariaDB image"
  docker pull photoprism/photoprism:latest || log "⚠️ Failed to pull PhotoPrism image"
}

# Run OS-specific installation
case "$INSTALL_TYPE" in
  linux)
    install_linux
    ;;
  macos)
    install_macos
    ;;
  windows)
    install_windows
    ;;
esac

# Common configuration steps
verify_docker
configure_photoprism
pull_images

log "Installation completed successfully!"
log "To start PhotoPrism2, run:"
log "  docker-compose up -d"
log ""
log "For best practice Docker builds, run:"
log "  ./scripts/run-build.sh"
log ""
log "To access PhotoPrism2:"
log "  http://localhost:2342/"
log "  Username: admin"
log "  Password: (check docker/secrets/photoprism_admin_password.txt)"
log ""
log "Installation log saved to: $LOGFILE"
