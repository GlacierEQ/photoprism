#!/bin/bash
# PhotoPrism2 Docker Build Performance Benchmarking
# Measures build performance across different build configurations

set -eo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RESULTS_DIR="${PROJECT_ROOT}/build/benchmark"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
REPORT_FILE="${RESULTS_DIR}/build-benchmark-${TIMESTAMP}.json"
DOCKERFILE="${PROJECT_ROOT}/Dockerfile"

# Create benchmark directory if it doesn't exist
mkdir -p "${RESULTS_DIR}"

# Test configurations - build options to benchmark
declare -A TEST_CONFIGS=(
  ["default"]=""
  ["no-cache"]="--no-cache"
  ["buildkit"]="DOCKER_BUILDKIT=1"
  ["buildkit-no-cache"]="DOCKER_BUILDKIT=1 --no-cache"
  ["custom-target"]="--target=backend-builder"
)

# Default options
ITERATIONS="${ITERATIONS:-3}"
CLEAN_AFTER="${CLEAN_AFTER:-true}"
GENERATE_REPORT="${GENERATE_REPORT:-true}"
GENERATE_CHART="${GENERATE_CHART:-false}"
TEST_NAME="${TEST_NAME:-benchmark-${TIMESTAMP}}"
TEST_DESCRIPTION="${TEST_DESCRIPTION:-Docker build performance benchmark}"

# Output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
  local level="$1"
  local message="$2"
  local color="${NC}"

  case "$level" in
    "INFO") color="${BLUE}" ;;
    "SUCCESS") color="${GREEN}" ;;
    "WARN") color="${YELLOW}" ;;
    "ERROR") color="${RED}" ;;
  esac

  echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [${level}]${NC} ${message}"
}

# Show help
show_help() {
  echo "PhotoPrism2 Docker Build Performance Benchmarking"
  echo ""
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  --iterations N      Number of test iterations (default: 3)"
  echo "  --no-clean          Don't clean up after benchmarks"
  echo "  --no-report         Don't generate JSON report"
  echo "  --chart             Generate performance chart (requires gnuplot)"
  echo "  --name NAME         Test name for reports"
  echo "  --description DESC  Test description"
  echo "  --configs 'c1,c2'   Comma-separated list of configs to test:"
  echo "                      (default,no-cache,buildkit,buildkit-no-cache,custom-target)"
  echo "  --help              Show this help message"
  echo ""
  exit 0
}

# Parse command line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --iterations)
        ITERATIONS="$2"
        shift 2
        ;;
      --no-clean)
        CLEAN_AFTER="false"
        shift
        ;;
      --no-report)
        GENERATE_REPORT="false"
        shift
        ;;
      --chart)
        GENERATE_CHART="true"
        shift
        ;;
      --name)
        TEST_NAME="$2"
        shift 2
        ;;
      --description)
        TEST_DESCRIPTION="$2"
        shift 2
        ;;
      --configs)
        IFS=',' read -r -a SELECTED_CONFIGS <<< "$2"
        shift 2
        ;;
      --help)
        show_help
        ;;
      *)
        log "ERROR" "Unknown option: $1"
        show_help
        ;;
    esac
  done
}

# Check Docker installation
check_docker() {
  log "INFO" "Checking Docker installation..."

  if ! command -v docker &> /dev/null; then
    log "ERROR" "Docker is not installed or not in PATH"
    exit 1
  fi

  log "INFO" "Docker is installed: $(docker --version)"
}

# Collect system information
collect_system_info() {
  log "INFO" "Collecting system information..."

  local info_file="${RESULTS_DIR}/system-info-${TIMESTAMP}.json"

  # Get CPU info
  local cpu_model=$(grep -m 1 "model name" /proc/cpuinfo 2>/dev/null | cut -d ':' -f 2 | xargs || echo "Unknown")
  local cpu_cores=$(grep -c "processor" /proc/cpuinfo 2>/dev/null || echo "Unknown")

  # Get memory info
  local mem_total=$(free -m | awk '/^Mem:/{print $2}')

  # Get disk info
  local disk_free=$(df -h . | awk 'NR==2 {print $4}')

  # Get Docker info
  local docker_version=$(docker --version | awk '{print $3}' | tr -d ',')
  local docker_storage_driver=$(docker info --format '{{.Driver}}')

  # Get OS info
  local os_name=$(uname -s)
  local os_version=$(uname -r)

  # Write to JSON file
  cat > "$info_file" << EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "system": {
    "os": "${os_name}",
    "version": "${os_version}",
    "cpu": {
      "model": "${cpu_model}",
      "cores": ${cpu_cores}
    },
    "memory": {
      "total_mb": ${mem_total}
    },
    "disk": {
      "free": "${disk_free}"
    }
  },
  "docker": {
    "version": "${docker_version}",
    "storage_driver": "${docker_storage_driver}"
  }
}
EOF

  log "INFO" "System information collected: $info_file"

  # Return the path to the info file
  echo "$info_file"
}

# Clean Docker images
clean_images() {
  log "INFO" "Cleaning up Docker images..."

  # Get the image prefix
  local prefix="photoprism2-benchmark"

  # Find and remove all benchmark images
  local images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^${prefix}" || echo "")

  if [ -n "$images" ]; then
    log "INFO" "Removing benchmark images..."
    echo "$images" | xargs docker rmi -f
  else
    log "INFO" "No benchmark images to clean up"
  fi
}

# Run a single benchmark
run_benchmark() {
  local config_name="$1"
  local config_args="${TEST_CONFIGS[$config_name]}"
  local iteration="$2"
  local image_tag="photoprism2-benchmark:${config_name}-${iteration}"
  local results=()

  log "INFO" "Running benchmark [${config_name}] iteration ${iteration}..."

  # Parse build arguments
  read -ra build_args <<< "$config_args"

  # Build array with all arguments
  local all_args=("build" "-t" "$image_tag" "-f" "$DOCKERFILE")

  # Apply environment variables if needed
  if [[ "$config_args" == *"DOCKER_BUILDKIT=1"* ]]; then
    export DOCKER_BUILDKIT=1
    # Remove this from the build args
    config_args=${config_args/DOCKER_BUILDKIT=1/}
    # Trim leading space if any
    config_args=$(echo "$config_args" | xargs)
  fi

  if [ -n "$config_args" ]; then
    all_args+=($config_args)
  fi

  # Add context path
  all_args+=("$PROJECT_ROOT")

  # Start timing
  local start_time=$(date +%s.%N)

  # Run the build
  docker "${all_args[@]}"

  # End timing
  local end_time=$(date +%s.%N)

  # Calculate duration
  local duration=$(echo "$end_time - $start_time" | bc)
  local duration_ms=$(echo "$duration * 1000" | bc | cut -d'.' -f1)

  # Get image info
  local image_size=$(docker image inspect "$image_tag" --format='{{.Size}}')
  local layer_count=$(docker image inspect "$image_tag" --format='{{len .RootFS.Layers}}')

  # Return results
  echo "$duration_ms $image_size $layer_count"
}

# Generate benchmark report
generate_report() {
  local results_file="$1"
  local system_info_file="$2"

  log "INFO" "Generating benchmark report..."

  # Compute averages
  local config_names=("${!TEST_CONFIGS[@]}")
  declare -A averages_time
  declare -A averages_size
  declare -A averages_layers

  # Initialize totals
  for config in "${config_names[@]}"; do
    averages_time["$config"]=0
    averages_size["$config"]=0
    averages_layers["$config"]=0
  done

  # Add up all values
  while IFS= read -r line; do
    local config=$(echo "$line" | cut -d' ' -f1)
    local duration=$(echo "$line" | cut -d' ' -f2)
    local size=$(echo "$line" | cut -d' ' -f3)
    local layers=$(echo "$line" | cut -d' ' -f4)

    averages_time["$config"]=$((averages_time["$config"] + duration))
    averages_size["$config"]=$((averages_size["$config"] + size))
    averages_layers["$config"]=$((averages_layers["$config"] + layers))
  done < "$results_file"

  # Divide by iterations
  for config in "${config_names[@]}"; do
    averages_time["$config"]=$((averages_time["$config"] / ITERATIONS))
    averages_size["$config"]=$((averages_size["$config"] / ITERATIONS))
    averages_layers["$config"]=$((averages_layers["$config"] / ITERATIONS))
  done

  # Create JSON report
  local report_file="${RESULTS_DIR}/${TEST_NAME}-report.json"

  # Start JSON file
  cat > "$report_file" << EOF
{
  "test_name": "${TEST_NAME}",
  "description": "${TEST_DESCRIPTION}",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "iterations": ${ITERATIONS},
  "results": {
EOF

  # Add each configuration
  local first=true
  for config in "${config_names[@]}"; do
    if [ "$first" = true ]; then
      first=false
    else
      echo "," >> "$report_file"
    fi

    cat >> "$report_file" << EOF
    "${config}": {
      "avg_build_time_ms": ${averages_time["$config"]},
      "avg_image_size_bytes": ${averages_size["$config"]},
      "avg_layer_count": ${averages_layers["$config"]},
      "build_args": "${TEST_CONFIGS[$config]}"
    }
EOF
  done

  # Add system info
  echo "," >> "$report_file"
  echo "  \"system_info\": " >> "$report_file"
  cat "$system_info_file" | sed '1d;$d' >> "$report_file"  # Remove first and last line (curly braces)

  # Close JSON file
  echo "}" >> "$report_file"

  log "SUCCESS" "Report generated: $report_file"

  # Return the path to the report
  echo "$report_file"
}

# Generate chart if requested
generate_chart() {
  local report_file="$1"

  if [ "$GENERATE_CHART" = "true" ]; then
    log "INFO" "Generating performance chart..."

    if ! command -v gnuplot &> /dev/null; then
      log "WARN" "gnuplot is not installed. Skipping chart generation."
      return
    fi

    # Extract values from JSON for plotting
    local chart_data="${RESULTS_DIR}/chart-data-${TIMESTAMP}.txt"
    local configs=($(jq -r '.results | keys[]' "$report_file"))

    # Create data file for gnuplot
    for config in "${configs[@]}"; do
      local time=$(jq -r ".results.\"${config}\".avg_build_time_ms" "$report_file")
      local size=$(jq -r ".results.\"${config}\".avg_image_size_bytes" "$report_file")
      echo "$config $time $size" >> "$chart_data"
    done

    # Create gnuplot script
    local gnuplot_script="${RESULTS_DIR}/chart-script-${TIMESTAMP}.gp"

    cat > "$gnuplot_script" << EOF
set terminal pngcairo size 1200,600 enhanced font 'Arial,10'
set output '${RESULTS_DIR}/${TEST_NAME}-chart.png'
set title 'Docker Build Performance - ${TEST_NAME}'
set style data histogram
set style histogram cluster gap 1
set style fill solid
set boxwidth 0.9
set grid ytics
set xtics rotate by -45
set ylabel 'Build Time (ms)'
set y2label 'Image Size (MB)'
set y2tics
set key top left

# Plot data
plot '${chart_data}' using 2:xtic(1) title 'Build Time (ms)' with histogram, \
     '' using 0:2:2 with labels offset 0,1 notitle, \
     '' using (column(0)-0.3):(column(3)/1024/1024) axes x1y2 title 'Image Size (MB)' with boxes lt rgb '#00FF00', \
     '' using (column(0)-0.3):(column(3)/1024/1024):(\$3/1024/1024) axes x1y2 with labels offset 0,1 notitle
EOF

    # Generate chart
    gnuplot "$gnuplot_script"

    log "SUCCESS" "Chart generated: ${RESULTS_DIR}/${TEST_NAME}-chart.png"

    # Clean up temporary files
    rm -f "$chart_data" "$gnuplot_script"
  fi
}

# Run all benchmarks
run_benchmarks() {
  local results_file="${RESULTS_DIR}/benchmark-raw-${TIMESTAMP}.txt"

  # Check if specific configs were selected
  if [ -z "${SELECTED_CONFIGS[*]:-}" ]; then
    SELECTED_CONFIGS=("${!TEST_CONFIGS[@]}")
  fi

  log "INFO" "Starting benchmark with ${ITERATIONS} iterations for each configuration"
  log "INFO" "Selected configurations: ${SELECTED_CONFIGS[*]}"

  # Run benchmarks
  for config_name in "${SELECTED_CONFIGS[@]}"; do
    if [ -z "${TEST_CONFIGS[$config_name]:-}" ]; then
      log "WARN" "Unknown configuration: $config_name - skipping"
      continue
    fi

    log "INFO" "Benchmarking configuration: $config_name"

    for ((i=1; i<=ITERATIONS; i++)); do
      local result=$(run_benchmark "$config_name" "$i")
      local duration=$(echo "$result" | cut -d' ' -f1)
      local image_size=$(echo "$result" | cut -d' ' -f2)
      local layer_count=$(echo "$result" | cut -d' ' -f3)

      log "SUCCESS" "Iteration $i completed in ${duration}ms (size: $(numfmt --to=iec-i --suffix=B --format="%.2f" "$image_size"), layers: $layer_count)"
      echo "$config_name $duration $image_size $layer_count" >> "$results_file"
    done
  done

  # Return the results file
  echo "$results_file"
}

# Main function
main() {
  log "INFO" "======== PhotoPrism2 Docker Build Benchmark ========"

  # Parse command line arguments
  parse_args "$@"

  # Check Docker installation
  check_docker

  # Clean previous benchmark images if requested
  if [ "$CLEAN_AFTER" = "true" ]; then
    clean_images
  fi

  # Collect system information
  local system_info_file=$(collect_system_info)

  # Run all benchmarks
  local results_file=$(run_benchmarks)

  # Generate report if requested
  if [ "$GENERATE_REPORT" = "true" ]; then
    local report_file=$(generate_report "$results_file" "$system_info_file")

    # Generate chart if requested
    generate_chart "$report_file"
  fi

  # Clean up after benchmarks if requested
  if [ "$CLEAN_AFTER" = "true" ]; then
    clean_images
  fi

  log "SUCCESS" "======== Benchmark Completed ========"
  log "INFO" "Results available in: $RESULTS_DIR"
}

# Execute main function
main "$@"
