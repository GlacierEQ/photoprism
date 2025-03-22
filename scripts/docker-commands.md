# Docker Commands Guide for PowerShell

## Using PowerShell with Docker

PowerShell may encounter parsing errors when running Docker commands that produce formatted output with certain characters like `[+]`. Here are ways to avoid these issues:

### Method 1: Using the docker-run.ps1 Script

We've provided a script that safely runs Docker commands:

```powershell
# Build a Docker image
.\scripts\docker-run.ps1 build -t photoprism2 .

# Run a Docker container
.\scripts\docker-run.ps1 run -p 2342:2342 photoprism2
```

### Method 2: Using Command Syntax

Use the call operator (`&`) to bypass PowerShell parsing:

```powershell
& docker build -t photoprism2 .
```

### Method 3: Using Invoke-Expression

```powershell
Invoke-Expression -Command "docker build -t photoprism2 ."
```

## Common Docker Commands for PhotoPrism

```powershell
# Build the PhotoPrism2 image
.\scripts\docker-run.ps1 build -t photoprism2 .

# Start Docker Compose services
.\scripts\docker-run.ps1 compose -f docker/docker-compose.prod.yml --env-file docker/.env.prod up -d

# View logs
.\scripts\docker-run.ps1 compose -f docker/docker-compose.prod.yml --env-file docker/.env.prod logs -f

# Stop services
.\scripts\docker-run.ps1 compose -f docker/docker-compose.prod.yml --env-file docker/.env.prod down
```
