# PhotoPrism Docker Deployment Guide

This guide explains how to deploy PhotoPrism using Docker and Docker Compose.

## Prerequisites

- Docker and Docker Compose installed
- At least 2GB of available RAM (4GB+ recommended)
- At least 10GB of free disk space (more for your photo collection)

## Quick Start

### Linux/macOS

1. Run the deployment script:

```bash
./deploy.sh
```

### Windows

1. Run the PowerShell deployment script:

```powershell
.\deploy.ps1
```

## Configuration Files

PhotoPrism uses the following configuration files:

- `docker/docker-compose.prod.yml` - The Docker Compose configuration
- `docker/.env.prod` - Production environment variables

**Note:** The deployment scripts automatically use these files. You should only need to edit `.env.prod` to customize your installation.

## Manual Setup

If you prefer to set up manually, follow these steps:

1. Create a production environment file:

```bash
cp docker/.env.example docker/.env.prod
```

2. Edit the environment file with your settings:

```bash
nano docker/.env.prod
```

3. Create the required directories:

```bash
mkdir -p storage originals import database backups redis
```

4. Pull the Docker images:

```bash
docker compose -f docker/docker-compose.prod.yml --env-file docker/.env.prod pull
```

5. Start the containers:

```bash
docker compose -f docker/docker-compose.prod.yml --env-file docker/.env.prod up -d
```

## Container Management

### View Logs

```bash
docker compose -f docker/docker-compose.prod.yml --env-file docker/.env.prod logs -f
```

### Stop Services

```bash
docker compose -f docker/docker-compose.prod.yml --env-file docker/.env.prod down
```

### Restart Services

```bash
docker compose -f docker/docker-compose.prod.yml --env-file docker/.env.prod restart
```

### Update to Latest Version

```bash
docker compose -f docker/docker-compose.prod.yml --env-file docker/.env.prod pull
docker compose -f docker/docker-compose.prod.yml --env-file docker/.env.prod down
docker compose -f docker/docker-compose.prod.yml --env-file docker/.env.prod up -d
```

## Configuration Options

### Important Environment Variables

- `PHOTOPRISM_ADMIN_PASSWORD`: Set a secure password for the admin user
- `PHOTOPRISM_SITE_URL`: The public URL of your PhotoPrism instance
- `PHOTOPRISM_SITE_TITLE`: The title of your PhotoPrism instance
- `PHOTOPRISM_STORAGE_PATH`: Path to the storage directory
- `PHOTOPRISM_ORIGINALS_PATH`: Path to store original photos
- `MYSQL_PASSWORD`: Database password
- `MYSQL_ROOT_PASSWORD`: Database root password

For a complete list of configuration options, see the comments in the `.env.prod` file.

## System Requirements

- **Minimum:** 2 CPU cores, 2GB RAM
- **Recommended:** 4 CPU cores, 8GB RAM
- **Storage:** Depends on your library size
  - Thumbnails require approximately 25% of the original storage size
  - Database will grow over time
  - Ensure at least 10GB free space beyond your photo collection size

## Troubleshooting

### PhotoPrism Container Exits Immediately

Check the logs:

```bash
docker compose -f docker/docker-compose.prod.yml --env-file docker/.env.prod logs photoprism
```

Common issues:
- Database connection problems
- Insufficient memory
- Permission problems with mounted volumes

### BRAINS Service Issues

If face recognition or NSFW detection isn't working:

```bash
docker compose -f docker/docker-compose.prod.yml --env-file docker/.env.prod logs brains
```

### Database Connection Errors

Verify database connection settings in your `.env.prod` file and check that the database container is running:

```bash
docker compose -f docker/docker-compose.prod.yml --env-file docker/.env.prod ps db
```
