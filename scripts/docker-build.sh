#!/bin/bash

# Advanced Docker Build Script
# This script implements best practices for building Docker images

# Configuration - modify as needed
IMAGE_NAME=${IMAGE_NAME:-"photoprism2"}
IMAGE_TAG=${IMAGE_TAG:-"latest"}
DOCKERFILE_PATH=${DOCKERFILE_PATH:-"./Dockerfile"}
BUILD_CONTEXT=${BUILD_CONTEXT:-"."}
PLATFORM=${PLATFORM:-"linux/amd64"}
CACHE_FROM=${CACHE_FROM:-""}
BUILD_ARGS=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --tag|-t)
      IMAGE_TAG="$2"
      shift 2
      ;;
    --file|-f)
      DOCKERFILE_PATH="$2"
      shift 2
      ;;
    --platform)
      PLATFORM="$2"
      shift 2
      ;;
    --no-cache)
      NO_CACHE="--no-cache"
      shift
      ;;
    --build-arg)
      BUILD_ARGS="$BUILD_ARGS --build-arg $2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  --tag, -t        Image tag (default: latest)"
      echo "  --file, -f       Path to Dockerfile (default: ./Dockerfile)"
      echo "  --platform       Build platform (default: linux/amd64)"
      echo "  --no-cache       Disable build cache"
      echo "  --build-arg      Add build argument (can be used multiple times)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

echo "🐳 PhotoPrism2 Docker Build"
echo "=========================="

# Check if Docker daemon is running
if ! docker info &> /dev/null; then
  echo "❌ Docker daemon is not running!"
  exit 1
fi

# Check if Dockerfile exists
if [ ! -f "$DOCKERFILE_PATH" ]; then
  echo "❌ Dockerfile not found at $DOCKERFILE_PATH"
  exit 1
fi

# Prepare cache options
CACHE_OPTIONS=""
if [ -n "$CACHE_FROM" ]; then
  CACHE_OPTIONS="--cache-from $CACHE_FROM"
fi

# Log build information
echo "📦 Building $IMAGE_NAME:$IMAGE_TAG"
echo "📄 Using Dockerfile: $DOCKERFILE_PATH"
echo "🖥️ Platform: $PLATFORM"

# Execute the optimized build command
docker buildx build \
  $NO_CACHE \
  $CACHE_OPTIONS \
  $BUILD_ARGS \
  --platform $PLATFORM \
  --file $DOCKERFILE_PATH \
  --tag "$IMAGE_NAME:$IMAGE_TAG" \
  --build-context app=$BUILD_CONTEXT \
  --progress=plain \
  --label "org.opencontainers.image.created=$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --label "org.opencontainers.image.version=$IMAGE_TAG" \
  $BUILD_CONTEXT

# Check if build was successful
if [ $? -eq 0 ]; then
  echo "✅ Build completed successfully!"
  echo "Image details:"
  docker image inspect "$IMAGE_NAME:$IMAGE_TAG" --format "{{.Size}}" | \
    awk '{ printf "Size: %.2f MB\n", $1/(1024*1024) }'
  echo "Run with: docker run -d --name photoprism2 $IMAGE_NAME:$IMAGE_TAG"
else
  echo "❌ Build failed!"
fi
