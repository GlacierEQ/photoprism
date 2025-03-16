#!/bin/bash
# PhotoPrism2 Docker Secrets Management Script
# Manages Docker secrets for secure credential handling

set -eo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SECRETS_DIR="${PROJECT_ROOT}/docker/secrets"
ENV_FILE="${PROJECT_ROOT}/.env"
TEMP_DIR=$(mktemp -d)

# Output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Secret identifier pattern validation regex
SECRET_NAME_REGEX='^[a-zA-Z0-9_\-]+$'

# Make sure secrets directory exists
mkdir -p "${SECRETS_DIR}"

# Logging function
log() {
  local level=$1
  local message=$2
  local color=$NC

  case $level in
    "INFO") color=$BLUE ;;
    "SUCCESS") color=$GREEN ;;
    "WARN") color=$YELLOW ;;
    "ERROR") color=$RED ;;
  esac

  echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [${level}]${NC} ${message}"
}

# Cleanup on exit
cleanup() {
  rm -rf "${TEMP_DIR}"
}

trap cleanup EXIT

# Check if Docker is installed
check_docker() {
  if ! command -v docker &> /dev/null; then
    log "ERROR" "Docker is not installed or not in PATH"
    exit 1
  fi

  # Check if Docker swarm is initialized for docker secrets
  if ! docker info | grep -q "Swarm: active"; then
    log "WARN" "Docker swarm is not active. Some operations will be simulated."
    log "WARN" "To enable Docker secrets, run: docker swarm init"
    SWARM_ACTIVE=false
  else
    SWARM_ACTIVE=true
  fi
}

# Show help
show_help() {
  echo "PhotoPrism2 Docker Secrets Management"
  echo ""
  echo "Usage: $0 [command] [options]"
  echo ""
  echo "Commands:"
  echo "  create NAME [VALUE]     Create a new secret (prompted if VALUE not provided)"
  echo "  delete NAME             Delete a secret"
  echo "  list                    List all secrets"
  echo "  rotate NAME             Rotate (update) an existing secret"
  echo "  export                  Export all secrets (secure format)"
  echo "  import FILE             Import secrets from export file"
  echo "  generate NAME [LENGTH]  Generate a random secret (default length: 32)"
  echo "  help                    Show this help message"
  echo ""
  echo "Options:"
  echo "  --file-only             Only create file-based secrets (no Docker secrets)"
  echo "  --docker-only           Only create Docker secrets (no files)"
  echo "  --env                   Also update .env file with secret value"
  echo ""
  exit 0
}

# Validate secret name
validate_secret_name() {
  local secret_name=$1

  if [[ ! $secret_name =~ $SECRET_NAME_REGEX ]]; then
    log "ERROR" "Invalid secret name: '$secret_name'. Use only letters, numbers, underscores, and hyphens."
    return 1
  fi

  return 0
}

# Create a secret
create_secret() {
  local secret_name=$1
  local secret_value=$2
  local file_only=${3:-false}
  local docker_only=${4:-false}
  local update_env=${5:-false}

  # Validate secret name
  if ! validate_secret_name "$secret_name"; then
    return 1
  fi

  # If no value provided, prompt for it
  if [ -z "$secret_value" ]; then
    # Use read with -s flag to hide the input
    read -s -p "Enter value for secret '$secret_name': " secret_value
    echo

    # Confirm the secret
    read -s -p "Confirm value for secret '$secret_name': " secret_confirm
    echo

    if [ "$secret_value" != "$secret_confirm" ]; then
      log "ERROR" "Secret values do not match"
      return 1
    fi
  fi

  # Create file-based secret
  if [ "$docker_only" = "false" ]; then
    local secret_file="${SECRETS_DIR}/${secret_name}.txt"

    # Check if secret already exists
    if [ -f "$secret_file" ]; then
      log "WARN" "Secret file already exists: $secret_file"
      read -p "Overwrite? (y/N): " overwrite

      if [[ ! $overwrite =~ ^[Yy]$ ]]; then
        log "INFO" "Secret creation cancelled"
        return 0
      fi
    fi

    # Write secret to file
    echo -n "$secret_value" > "$secret_file"
    chmod 600 "$secret_file"
    log "SUCCESS" "Secret file created: $secret_file"
  fi

  # Create Docker secret
  if [ "$file_only" = "false" ]; then
    if [ "$SWARM_ACTIVE" = "true" ]; then
      # Check if Docker secret already exists
      if docker secret inspect "$secret_name" &> /dev/null; then
        log "WARN" "Docker secret already exists: $secret_name"
        read -p "Rotate secret? (y/N): " rotate

        if [[ ! $rotate =~ ^[Yy]$ ]]; then
          log "INFO" "Secret rotation cancelled"
        else
          # Create a new secret with a temporary name
          echo -n "$secret_value" | docker secret create "${secret_name}_new" -

          # Update services to use the new secret (not implemented here)
          log "WARN" "Manual service update required to use the new secret"

          # Remove the old secret (warning, this will fail if services still use it)
          log "WARN" "Manual cleanup of old secret '$secret_name' required when no longer used"
        fi
      else
        # Create new Docker secret
        echo -n "$secret_value" | docker secret create "$secret_name" -
        log "SUCCESS" "Docker secret created: $secret_name"
      fi
    else
      log "INFO" "Docker swarm not active, skipping Docker secret creation"
    fi
  fi

  # Update .env file if requested
  if [ "$update_env" = "true" ] && [ -f "$ENV_FILE" ]; then
    local env_var_name=$(echo "$secret_name" | tr '[:lower:]' '[:upper:]')

    # Check if variable already exists in .env
    if grep -q "^${env_var_name}=" "$ENV_FILE"; then
      # Update existing variable
      sed -i "s|^${env_var_name}=.*|${env_var_name}=${secret_value}|" "$ENV_FILE"
    else
      # Add new variable
      echo "${env_var_name}=${secret_value}" >> "$ENV_FILE"
    fi

    log "SUCCESS" "Updated environment variable in .env file: ${env_var_name}"
  fi
}

# Delete a secret
delete_secret() {
  local secret_name=$1

  # Validate secret name
  if ! validate_secret_name "$secret_name"; then
    return 1
  fi

  # Delete file-based secret
  local secret_file="${SECRETS_DIR}/${secret_name}.txt"
  if [ -f "$secret_file" ]; then
    rm "$secret_file"
    log "SUCCESS" "Secret file deleted: $secret_file"
  else
    log "WARN" "Secret file not found: $secret_file"
  fi

  # Delete Docker secret
  if [ "$SWARM_ACTIVE" = "true" ]; then
    if docker secret inspect "$secret_name" &> /dev/null; then
      log "WARN" "Deleting Docker secret: $secret_name"
      log "WARN" "This will fail if the secret is in use by any service"

      if docker secret rm "$secret_name"; then
        log "SUCCESS" "Docker secret deleted: $secret_name"
      else
        log "ERROR" "Failed to delete Docker secret: $secret_name"
        log "ERROR" "It might be in use by active services"
      fi
    else
      log "WARN" "Docker secret not found: $secret_name"
    fi
  else
    log "INFO" "Docker swarm not active, skipping Docker secret deletion"
  fi
}

# List secrets
list_secrets() {
  log "INFO" "File-based secrets:"

  if [ -d "$SECRETS_DIR" ] && [ "$(ls -A "$SECRETS_DIR")" ]; then
    for secret_file in "${SECRETS_DIR}"/*.txt; do
      local secret_name=$(basename "$secret_file" .txt)
      local file_age=$(stat -c %y "$secret_file" 2>/dev/null || stat -f "%Sm" "$secret_file" 2>/dev/null)
      echo "  - ${secret_name} (updated: ${file_age})"
    done
  else
    echo "  No file-based secrets found"
  fi

  echo ""
  log "INFO" "Docker secrets:"

  if [ "$SWARM_ACTIVE" = "true" ]; then
    local docker_secrets=$(docker secret ls --format "{{.Name}}" 2>/dev/null)

    if [ -n "$docker_secrets" ]; then
      while read -r secret_name; do
        local creation_time=$(docker secret inspect --format='{{.CreatedAt}}' "$secret_name")
        echo "  - ${secret_name} (created: ${creation_time})"
      done <<< "$docker_secrets"
    else
      echo "  No Docker secrets found"
    fi
  else
    echo "  Docker swarm not active"
  fi
}

# Generate a random secret
generate_secret() {
  local secret_name=$1
  local length=${2:-32}
  local file_only=${3:-false}
  local docker_only=${4:-false}
  local update_env=${5:-false}

  # Validate secret name
  if ! validate_secret_name "$secret_name"; then
    return 1
  fi

  # Generate a secure random string
  local secret_value=""
  if command -v openssl &> /dev/null; then
    secret_value=$(openssl rand -base64 $((length * 3/4)) | tr -d '\n' | cut -c1-$length)
  else
    log "WARN" "OpenSSL not found, using less secure method"
    secret_value=$(cat /dev/urandom 2>/dev/null | tr -dc 'a-zA-Z0-9!@#$%^&*()_+{}|:<>?=' | head -c "$length")
  fi

  # Create the secret
  create_secret "$secret_name" "$secret_value" "$file_only" "$docker_only" "$update_env"

  log "SUCCESS" "Generated random secret: $secret_name (length: $length)"
}

# Rotate (update) an existing secret
rotate_secret() {
  local secret_name=$1
  local file_only=${2:-false}
  local docker_only=${3:-false}
  local update_env=${4:-false}

  # Validate secret name
  if ! validate_secret_name "$secret_name"; then
    return 1
  fi

  # Check if secret exists
  local secret_file="${SECRETS_DIR}/${secret_name}.txt"
  local secret_exists=false

  if [ -f "$secret_file" ]; then
    secret_exists=true
  elif [ "$SWARM_ACTIVE" = "true" ] && docker secret inspect "$secret_name" &> /dev/null; then
    secret_exists=true
  fi

  if [ "$secret_exists" = "false" ]; then
    log "ERROR" "Secret does not exist: $secret_name"
    return 1
  fi

  # Get new secret value
  read -s -p "Enter new value for secret '$secret_name': " secret_value
  echo

  # Confirm the secret
  read -s -p "Confirm new value for secret '$secret_name': " secret_confirm
  echo

  if [ "$secret_value" != "$secret_confirm" ]; then
    log "ERROR" "Secret values do not match"
    return 1
  fi

  # Create the secret (will handle rotation)
  create_secret "$secret_name" "$secret_value" "$file_only" "$docker_only" "$update_env"

  log "SUCCESS" "Secret rotated: $secret_name"
}

# Export secrets to a secure file
export_secrets() {
  local export_file="${1:-${PROJECT_ROOT}/docker/secrets/secrets-export-$(date +%Y%m%d-%H%M%S).enc}"

  # Check if any secrets exist
  if [ ! -d "$SECRETS_DIR" ] || [ -z "$(ls -A "$SECRETS_DIR")" ]; then
    log "ERROR" "No file-based secrets found to export"
    return 1
  fi

  # Generate a temporary file with JSON structure
  local temp_file="${TEMP_DIR}/secrets.json"

  echo "{" > "$temp_file"
  echo "  \"exported_at\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"," >> "$temp_file"
  echo "  \"secrets\": {" >> "$temp_file"

  local first=true
  for secret_file in "${SECRETS_DIR}"/*.txt; do
    if [ "$first" = "true" ]; then
      first=false
    else
      echo "," >> "$temp_file"
    fi

    local secret_name=$(basename "$secret_file" .txt)
    local secret_value=$(cat "$secret_file")
    local file_age=$(stat -c %y "$secret_file" 2>/dev/null || stat -f "%Sm" "$secret_file" 2>/dev/null)

    echo -n "    \"${secret_name}\": {\"value\": \"$(echo "$secret_value" | base64)\", \"updated\": \"$file_age\"}" >> "$temp_file"
  done

  echo "" >> "$temp_file"
  echo "  }" >> "$temp_file"
  echo "}" >> "$temp_file"

  # Encrypt the file
  read -s -p "Enter encryption password: " password
  echo
  read -s -p "Confirm encryption password: " password_confirm
  echo

  if [ "$password" != "$password_confirm" ]; then
    log "ERROR" "Passwords do not match"
    return 1
  fi

  # Create output directory if it doesn't exist
  mkdir -p "$(dirname "$export_file")"

  # Use OpenSSL to encrypt
  openssl enc -aes-256-cbc -salt -pbkdf2 -iter 10000 -in "$temp_file" -out "$export_file" -pass "pass:$password"

  log "SUCCESS" "Secrets exported to: $export_file"
  log "INFO" "Keep the encryption password safe, you'll need it to import the secrets"
}

# Import secrets from an export file
import_secrets() {
  local import_file="$1"
  local file_only=${2:-false}
  local docker_only=${3:-false}
  local update_env=${4:-false}

  if [ ! -f "$import_file" ]; then
    log "ERROR" "Import file not found: $import_file"
    return 1
  fi

  # Decrypt the file
  read -s -p "Enter decryption password: " password
  echo

  local temp_file="${TEMP_DIR}/secrets.json"

  if ! openssl enc -aes-256-cbc -d -salt -pbkdf2 -iter 10000 -in "$import_file" -out "$temp_file" -pass "pass:$password"; then
    log "ERROR" "Failed to decrypt file. Wrong password?"
    return 1
  fi

  # Validate JSON format
  if ! jq empty "$temp_file" 2>/dev/null; then
    log "ERROR" "Invalid JSON format in decrypted file"
    return 1
  fi

  # Read and create each secret
  local secret_count=0
  local export_date=$(jq -r '.exported_at' "$temp_file")

  log "INFO" "Importing secrets exported at: $export_date"

  while read -r secret_name; do
    local secret_value=$(jq -r ".secrets.\"$secret_name\".value" "$temp_file" | base64 --decode)
    create_secret "$secret_name" "$secret_value" "$file_only" "$docker_only" "$update_env"
    secret_count=$((secret_count + 1))
  done < <(jq -r '.secrets | keys[]' "$temp_file")

  log "SUCCESS" "Imported $secret_count secrets"
}

# Main function
main() {
  # Check if Docker is installed
  check_docker

  # Parse command line arguments
  local command="${1:-help}"
  shift || true

  case "$command" in
    create)
      local secret_name="$1"
      local secret_value="$2"
      local file_only="false"
      local docker_only="false"
      local update_env="false"

      shift 2 || true

      # Parse additional options
      while [[ $# -gt 0 ]]; do
        case $1 in
          --file-only)
            file_only="true"
            shift
            ;;
          --docker-only)
            docker_only="true"
            shift
            ;;
          --env)
            update_env="true"
            shift
            ;;
          *)
            log "ERROR" "Unknown option: $1"
            show_help
            ;;
        esac
      done

      create_secret "$secret_name" "$secret_value" "$file_only" "$docker_only" "$update_env"
      ;;

    delete)
      local secret_name="$1"
      delete_secret "$secret_name"
      ;;

    list)
      list_secrets
      ;;

    rotate)
      local secret_name="$1"
      local file_only="false"
      local docker_only="false"
      local update_env="false"

      shift || true

      # Parse additional options
      while [[ $# -gt 0 ]]; do
        case $1 in
          --file-only)
            file_only="true"
            shift
            ;;
          --docker-only)
            docker_only="true"
            shift
            ;;
          --env)
            update_env="true"
            shift
            ;;
          *)
            log "ERROR" "Unknown option: $1"
            show_help
            ;;
        esac
      done

      rotate_secret "$secret_name" "$file_only" "$docker_only" "$update_env"
      ;;

    generate)
      local secret_name="$1"
      local length="${2:-32}"
      local file_only="false"
      local docker_only="false"
      local update_env="false"

      # Adjust shifts based on provided arguments
      if [ -n "$1" ]; then shift; fi
      if [ -n "$1" ]; then shift; fi

      # Parse additional options
      while [[ $# -gt 0 ]]; do
        case $1 in
          --file-only)
            file_only="true"
            shift
            ;;
          --docker-only)
            docker_only="true"
            shift
            ;;
          --env)
            update_env="true"
            shift
            ;;
          *)
            log "ERROR" "Unknown option: $1"
            show_help
            ;;
        esac
      done

      generate_secret "$secret_name" "$length" "$file_only" "$docker_only" "$update_env"
      ;;

    export)
      local export_file="$1"
      export_secrets "$export_file"
      ;;

    import)
      local import_file="$1"
      local file_only="false"
      local docker_only="false"
      local update_env="false"

      shift || true

      # Parse additional options
      while [[ $# -gt 0 ]]; do
        case $1 in
          --file-only)
            file_only="true"
            shift
            ;;
          --docker-only)
            docker_only="true"
            shift
            ;;
          --env)
            update_env="true"
            shift
            ;;
          *)
            log "ERROR" "Unknown option: $1"
            show_help
            ;;
        esac
      done

      import_secrets "$import_file" "$file_only" "$docker_only" "$update_env"
      ;;

    help|--help|-h)
      show_help
      ;;

    *)
      log "ERROR" "Unknown command: $command"
      show_help
      ;;
  esac
}

# Run main function with all arguments
main "$@"
