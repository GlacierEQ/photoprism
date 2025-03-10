<#
.SYNOPSIS
    PowerShell script to run the PhotoPrism deployment
.DESCRIPTION
    This script provides a Windows-friendly way to deploy PhotoPrism
    using Docker, Git Bash, or WSL.
#>

# Set strict mode and error action preference
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Configuration
$ScriptPath = "scripts/deploy-production.sh"
$GitBashPath = "C:\Program Files\Git\bin\bash.exe"
$DockerDesktopPath = "$env:LOCALAPPDATA\Docker\Docker\Docker Desktop.exe"

# Output formatting
Write-Host "PhotoPrism Deployment Launcher" -ForegroundColor Cyan
Write-Host "============================" -ForegroundColor Cyan

# Function to check if a command exists
function Test-Command {
    param ([string]$Command)
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try { if (Get-Command $Command) { return $true } }
    catch { return $false }
    finally { $ErrorActionPreference = $oldPreference }
}

# Ensure environment setup
$setupScriptPath = ".\Setup-Environment.ps1"
if (-not (Test-Path $setupScriptPath)) {
    Write-Host "ERROR: Environment setup script not found: $setupScriptPath" -ForegroundColor Red
    Write-Host "Please ensure the setup script exists or re-run the environment setup." -ForegroundColor Red
    exit 1
}

# Check if Docker is available
if (-not (Test-Command "docker")) {
    Write-Host "ERROR: Docker is not available in your PATH." -ForegroundColor Red
    
    if (Test-Path $DockerDesktopPath) {
        Write-Host "Docker Desktop appears to be installed but not running." -ForegroundColor Yellow
        Write-Host "Would you like to start Docker Desktop now? (Y/n)" -NoNewline -ForegroundColor Yellow
        $response = Read-Host
        
        if ($response -eq "" -or $response -eq "y" -or $response -eq "Y") {
            Write-Host "Starting Docker Desktop..." -ForegroundColor Cyan
            Start-Process $DockerDesktopPath
            Write-Host "Please wait for Docker to start completely, then run this script again." -ForegroundColor Cyan
        } else {
            Write-Host "Please start Docker Desktop manually, then run this script again." -ForegroundColor Cyan
        }
    } else {
        Write-Host "Docker Desktop does not appear to be installed." -ForegroundColor Red
        Write-Host "Please run .\Setup-Environment.ps1 to set up your environment." -ForegroundColor Cyan
    }
    
    exit 1
}

# Check if the script exists
if (-not (Test-Path $ScriptPath)) {
    Write-Host "ERROR: Deployment script not found at: $ScriptPath" -ForegroundColor Red
    Write-Host "Creating basic bash script structure..." -ForegroundColor Yellow
    
    $deployScriptContent = @'
#!/bin/bash
set -e

# PhotoPrism Deployment Script
echo "Starting PhotoPrism deployment..."

# Run docker commands
echo "Building Docker image..."
docker build -t photoprism:latest -f Dockerfile .

echo "Running PhotoPrism container..."
docker run -d -p 2342:2342 \
  -v "./storage:/photoprism/storage" \
  -v "./originals:/photoprism/storage/originals" \
  --name photoprism_app \
  photoprism:latest

echo "PhotoPrism should now be available at http://localhost:2342"
'@

    New-Item -Path "scripts" -ItemType Directory -Force | Out-Null
    $deployScriptContent | Set-Content -Path $ScriptPath -NoNewline
    Write-Host "Created a basic deployment script at $ScriptPath" -ForegroundColor Green
}

# Choose execution method
$method = "docker"
if (Test-Path $GitBashPath) {
    $method = "gitbash"
} elseif (Test-Command "wsl") {
    $method = "wsl"
}

# Execute based on the selected method
switch ($method) {
    "gitbash" {
        Write-Host "Using Git Bash to run the deployment script..." -ForegroundColor Green
        & $GitBashPath -c "cd `"$PWD`" && chmod +x $ScriptPath && ./$ScriptPath"
        $exitCode = $LASTEXITCODE
    }
    "wsl" {
        Write-Host "Using WSL to run the deployment script..." -ForegroundColor Green
        $WslPath = wsl wslpath -a "$PWD\$ScriptPath"
        & wsl chmod +x $WslPath
        & wsl cd `$(wslpath -a "'$PWD'") `&`& $WslPath
        $exitCode = $LASTEXITCODE
    }
    "docker" {
        Write-Host "Using Docker directly..." -ForegroundColor Yellow
        
        Write-Host "Checking if Docker is running..." -ForegroundColor Cyan
        try {
            $dockerInfo = docker info 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Docker is not running"
            }
        } catch {
            Write-Host "ERROR: Docker doesn't seem to be running." -ForegroundColor Red
            Write-Host "Please start Docker Desktop and try again." -ForegroundColor Yellow
            exit 1
        }
        
        Write-Host "Building Docker image..." -ForegroundColor Cyan
        docker build -t photoprism:latest -f Dockerfile .
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: Docker build failed." -ForegroundColor Red
            exit $LASTEXITCODE
        }
        
        Write-Host "Running PhotoPrism container..." -ForegroundColor Cyan
        # Check if container already exists
        $containerExists = docker ps -a --filter "name=photoprism_app" --format "{{.Names}}" | Where-Object { $_ -eq "photoprism_app" }
        if ($containerExists) {
            Write-Host "Container 'photoprism_app' already exists, removing it..." -ForegroundColor Yellow
            docker rm -f photoprism_app
        }
        
        docker run -d -p 2342:2342 `
          -v "${PWD}/storage:/photoprism/storage" `
          -v "${PWD}/originals:/photoprism/storage/originals" `
          --name photoprism_app `
          photoprism:latest
          
        $exitCode = $LASTEXITCODE
        
        if ($exitCode -eq 0) {
            Write-Host "`nPhotoprism is now running!" -ForegroundColor Green
            Write-Host "Access the web interface at: http://localhost:2342" -ForegroundColor Cyan
            Write-Host "Default login: admin / photoprism" -ForegroundColor Cyan
            
            # Ask if user wants to open the browser
            $openBrowser = Read-Host "Would you like to open PhotoPrism in your browser? (Y/n)"
            if ($openBrowser -eq "" -or $openBrowser -eq "y" -or $openBrowser -eq "Y") {
                Start-Process "http://localhost:2342"
            }
        }
    }
}

exit $exitCode
