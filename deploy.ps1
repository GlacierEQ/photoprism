# PhotoPrism Production Deployment Script for Windows
# --------------------------------------------------

# Configuration
$DockerComposeFile = "docker\docker-compose.prod.yml"
$EnvFile = "docker\.env.prod"

# Set console colors for output
$host.UI.RawUI.ForegroundColor = "Cyan"
Write-Host "========================================="
Write-Host " PhotoPrism Production Deployment Script "
Write-Host "========================================="
$host.UI.RawUI.ForegroundColor = "White"
Write-Host ""

# Check if Docker is installed
try {
    docker --version | Out-Null
}
catch {
    Write-Host "Docker not found. Please install Docker Desktop for Windows first." -ForegroundColor Yellow
    exit 1
}

# Check if environment file exists
if (-not (Test-Path $EnvFile)) {
    Write-Host "Environment file $EnvFile not found. Creating from example..." -ForegroundColor Yellow

    if (Test-Path "docker\.env.example") {
        Copy-Item "docker\.env.example" $EnvFile
    }
    elseif (Test-Path "docker\.env") {
        Copy-Item "docker\.env" $EnvFile
    }
    else {
        New-Item -ItemType File -Path $EnvFile
    }

    Write-Host "Please edit $EnvFile with your settings before continuing." -ForegroundColor Yellow
    Write-Host "Press Enter to continue or Ctrl+C to abort..." -ForegroundColor Yellow
    Read-Host
}

# Create required directories
Write-Host "Creating required directories..." -ForegroundColor Green
New-Item -ItemType Directory -Force -Path storage, originals, import, database, backups, redis | Out-Null

# Pull Docker images
Write-Host "Pulling latest Docker images..." -ForegroundColor Green
docker compose -f $DockerComposeFile --env-file $EnvFile pull

# Stop any existing containers
Write-Host "Stopping any existing containers..." -ForegroundColor Green
try {
    docker compose -f $DockerComposeFile --env-file $EnvFile down --remove-orphans
}
catch {
    # Ignore errors if no containers are running
}

# Start containers
Write-Host "Starting PhotoPrism containers..." -ForegroundColor Green
docker compose -f $DockerComposeFile --env-file $EnvFile up -d

# Wait a bit for services to start
Start-Sleep -Seconds 5

# Verify deployment
Write-Host "Verifying deployment..." -ForegroundColor Green
$photoprismRunning = docker compose -f $DockerComposeFile --env-file $EnvFile ps | Select-String -Pattern "photoprism.*Up"
if ($photoprismRunning) {
    Write-Host "✓ PhotoPrism started successfully" -ForegroundColor Green
}
else {
    Write-Host "⚠ PhotoPrism container may not have started properly. Checking logs:" -ForegroundColor Yellow
    docker compose -f $DockerComposeFile --env-file $EnvFile logs photoprism
}

$brainsRunning = docker compose -f $DockerComposeFile --env-file $EnvFile ps | Select-String -Pattern "photoprism_brains.*Up"
if ($brainsRunning) {
    Write-Host "✓ BRAINS service started successfully" -ForegroundColor Green
}
else {
    Write-Host "⚠ BRAINS service may not have started properly. Checking logs:" -ForegroundColor Yellow
    docker compose -f $DockerComposeFile --env-file $EnvFile logs brains
}

# Extract site URL from environment
$envContent = Get-Content $EnvFile
$siteUrl = "http://localhost:2342"
$adminUser = "admin"

foreach ($line in $envContent) {
    if ($line -match "PHOTOPRISM_SITE_URL=(.*)") {
        $siteUrl = $matches[1]
    }
    if ($line -match "PHOTOPRISM_ADMIN_USER=(.*)") {
        $adminUser = $matches[1]
    }
}

Write-Host ""
$host.UI.RawUI.ForegroundColor = "Cyan"
Write-Host "🎉 PhotoPrism deployment complete!"
Write-Host "📷 Access your photo library at: $siteUrl"
Write-Host "👤 Username: $adminUser"
Write-Host "🔑 Password: (as specified in $EnvFile)"
Write-Host ""
$host.UI.RawUI.ForegroundColor = "Yellow"

Write-Host "Useful commands:"
Write-Host "  View logs: docker compose -f $DockerComposeFile --env-file $EnvFile logs -f"
Write-Host "  Stop services: docker compose -f $DockerComposeFile --env-file $EnvFile down"
Write-Host "  Restart services: docker compose -f $DockerComposeFile --env-file $EnvFile restart"

$host.UI.RawUI.ForegroundColor = "White"
Write-Host ""
