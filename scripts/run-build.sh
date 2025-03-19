#!/bin/bash

# Helper script to demonstrate best practice Docker builds
# Shows examples of running docker-build.sh with optimal configurations

# Ensure scripts are executable
chmod +x scripts/docker-build.sh

echo "🚀 PhotoPrism2 Build Examples"
echo "============================"

# Function to explain and run a build command
run_build_example() {
  local title="$1"
  local command="$2"
  local explanation="$3"

  echo -e "\n📋 Example: $title"
  echo -e "⚙️  $explanation"
  echo -e "$ $command\n"

  # Ask user if they want to run this example
  read -p "Run this build? (y/n): " choice
  if [[ $choice =~ ^[Yy]$ ]]; then
    eval "$command"
  fi
}

# Example 1: Basic optimized build
run_build_example "Basic Optimized Build" \
  "./scripts/docker-build.sh" \
  "Standard build with default optimization flags"

# Example 2: Multi-platform build
run_build_example "Multi-platform Build" \
  "./scripts/docker-build.sh --platform linux/amd64,linux/arm64" \
  "Build for multiple architectures (useful for deployment across different devices)"

# Example 3: Production build with version tag
run_build_example "Production Release Build" \
  "./scripts/docker-build.sh --tag v1.0.0 --build-arg NODE_ENV=production" \
  "Production build with semantic versioning and production environment"

# Example 4: Fresh build without cache
run_build_example "Clean Build (No Cache)" \
  "./scripts/docker-build.sh --tag latest-fresh --no-cache" \
  "Rebuilds everything from scratch, ignoring cache (useful for solving dependency issues)"

# Example 5: Custom Dockerfile location
run_build_example "Custom Dockerfile" \
  "./scripts/docker-build.sh --file ./docker/Dockerfile.slim --tag slim" \
  "Using an alternative Dockerfile for specialized builds"

echo -e "\n✨ Build Options Summary:"
echo "• --tag (-t): Set version tag (follow semantic versioning)"
echo "• --platform: Target architectures (linux/amd64, linux/arm64, etc.)"
echo "• --no-cache: Force rebuild without using Docker cache"
echo "• --file (-f): Use alternative Dockerfile"
echo "• --build-arg: Pass environment variables to build process"

echo -e "\n🔍 For complete options: ./scripts/docker-build.sh --help"
