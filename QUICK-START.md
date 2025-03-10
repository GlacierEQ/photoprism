# PhotoPrism Quick Start Guide

## One-Step Deployment

### Linux/macOS

```bash
./deploy.sh
```

### Windows

```powershell
.\deploy.ps1
```

## Manual Commands

If you prefer the manual approach:

```bash
# 1. Create directories
mkdir -p storage originals import database backups redis

# 2. Start the containers
docker compose -f docker/docker-compose.prod.yml --env-file docker/.env.prod up -d
```

## Common Operations

```bash
# View logs
docker compose -f docker/docker-compose.prod.yml --env-file docker/.env.prod logs -f

# Stop all containers
docker compose -f docker/docker-compose.prod.yml --env-file docker/.env.prod down

# Update to latest version
docker compose -f docker/docker-compose.prod.yml --env-file docker/.env.prod pull
docker compose -f docker/docker-compose.prod.yml --env-file docker/.env.prod down
docker compose -f docker/docker-compose.prod.yml --env-file docker/.env.prod up -d
```

For detailed configuration and options, see [DOCKER-SETUP.md](DOCKER-SETUP.md)
