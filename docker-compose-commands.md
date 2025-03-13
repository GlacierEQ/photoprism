# Docker Compose Commands for PhotoPrism

## Start PhotoPrism (Production)

```bash
# Navigate to your PhotoPrism directory
cd /path/to/photoprism2

# Start using Docker Compose
docker compose -f docker/docker-compose.prod.yml --env-file docker/.env.prod up -d
```

## Alternative: Use Deployment Scripts

These scripts handle directory creation and proper startup:

### Linux/macOS
```bash
./deploy.sh
```

### Windows
```powershell
.\deploy.ps1
```

## Useful Management Commands

```bash
# View logs
docker compose -f docker/docker-compose.prod.yml --env-file docker/.env.prod logs -f

# Stop all containers
docker compose -f docker/docker-compose.prod.yml --env-file docker/.env.prod down

# Restart services
docker compose -f docker/docker-compose.prod.yml --env-file docker/.env.prod restart
```
