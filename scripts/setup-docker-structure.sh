#!/bin/bash
set -e

# Create Docker directory structure
mkdir -p docker/compose
mkdir -p docker/config
mkdir -p docker/scripts
mkdir -p docker/secrets
mkdir -p docker/monitoring/prometheus
mkdir -p docker/monitoring/grafana
mkdir -p docker/monitoring/loki
mkdir -p docker/nginx
mkdir -p docker/backup

echo "Docker directory structure created successfully"
