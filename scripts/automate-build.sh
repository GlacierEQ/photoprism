#!/bin/bash

# Unified Build Script for Docker Images
# Combines functionalities of docker-build.ps1 and run-build.sh

# Default values
TAG="latest"
FILE="./Dockerfile"
PLATFORM="linux/amd64"
NO_CACHE=""
BUILD_ARGS=()

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -t, --tag <tag>         Set image tag (default: latest)"
    echo "  -f, --file <path>       Path to Dockerfile (default: ./Dockerfile)"
    echo "  --platform <platform>    Build platform (default: linux/amd64)"
    echo "  --no-cache               Disable build cache"
    echo "  --build-arg <arg>       Add build arguments (can be used multiple times)"
    echo "  -h, --help              Display this help message"
    exit 1
}

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -t|--tag) TAG="$2"; shift ;;
        -f|--file) FILE="$2"; shift ;;
        --platform) PLATFORM="$2"; shift ;;
        --no-cache) NO_CACHE="--no-cache" ;;
        --build-arg) BUILD_ARGS+=("$2"); shift ;;
        -h|--help) usage ;;
        *) echo "Unknown parameter: $1"; usage ;;
    esac
    shift
done

# Check if Docker daemon is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker daemon is not running!"
    exit 1
fi

# Check if Dockerfile exists
if [[ ! -f "$FILE" ]]; then
    echo "❌ Dockerfile not found at $FILE"
    exit 1
fi

# Prepare build arguments
BUILD_ARGS_STRING=""
for arg in "${BUILD_ARGS[@]}"; do
    BUILD_ARGS_STRING+=" --build-arg $arg"
done

# Prepare the build command
BUILD_COMMAND="docker buildx build $NO_CACHE $BUILD_ARGS_STRING --platform $PLATFORM --file $FILE --tag $TAG ."

# Execute the build command
echo "Executing build command: $BUILD_COMMAND"
eval "$BUILD_COMMAND"

# Check if build was successful
if [[ $? -eq 0 ]]; then
    echo "✅ Build completed successfully!"
else
    echo "❌ Build failed!"
fi
