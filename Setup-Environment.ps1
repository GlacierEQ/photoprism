<#
.SYNOPSIS
    Sets up the environment for PhotoPrism deployment
.DESCRIPTION
    This script checks for required dependencies (Docker, Git Bash or WSL)
    and guides the user through installation if needed.
#>

# Set strict mode and error action preference
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Output formatting settings
$InformationColor = "Cyan"
$WarningColor = "Yellow"
$ErrorColor = "Red"
$SuccessColor = "Green"

function Write-Step {
    param ([string]$Message)
    Write-Host "`n[STEP] $Message" -ForegroundColor $InformationColor
    Write-Host "-----------------------------------------" -ForegroundColor $InformationColor
}

function Test-CommandExists {
    param ([string]$Command)
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try { if (Get-Command $Command) { return $true } }
    catch { return $false }
    finally { $ErrorActionPreference = $oldPreference }
}

function Test-PathExists {
    param ([string]$Path)
    return Test-Path $Path
}

function Open-InstallationPage {
    param ([string]$Url)
    Write-Host "Opening installation page in your default browser..." -ForegroundColor $InformationColor
    Start-Process $Url
}

# Main function to check Docker installation
function Test-DockerInstallation {
    Write-Step "Checking Docker Installation"
    
    if (Test-CommandExists "docker") {
        Write-Host "Docker is installed and available in your PATH." -ForegroundColor $SuccessColor
        return $true
    } else {
        # Check for Docker Desktop installation
        $dockerDesktopPath = "$env:LOCALAPPDATA\Docker\Docker\Docker Desktop.exe"
        if (Test-PathExists $dockerDesktopPath) {
            Write-Host "Docker Desktop is installed but not available in your PATH." -ForegroundColor $WarningColor
            Write-Host "Please start Docker Desktop and try again." -ForegroundColor $WarningColor
            
            $startDocker = Read-Host "Would you like to start Docker Desktop now? (Y/n)"
            if ($startDocker -eq "" -or $startDocker -eq "y" -or $startDocker -eq "Y") {
                Write-Host "Starting Docker Desktop..." -ForegroundColor $InformationColor
                Start-Process $dockerDesktopPath
                Write-Host "Please wait for Docker to start completely before proceeding." -ForegroundColor $InformationColor
                Read-Host "Press Enter when Docker is running"
            }
            
            return $false
        } else {
            Write-Host "Docker is not installed on this system." -ForegroundColor $ErrorColor
            Write-Host "Please install Docker Desktop for Windows:" -ForegroundColor $InformationColor
            Write-Host "https://docs.docker.com/desktop/install/windows-install/" -ForegroundColor $InformationColor
            
            $installDocker = Read-Host "Would you like to open the Docker installation page? (Y/n)"
            if ($installDocker -eq "" -or $installDocker -eq "y" -or $installDocker -eq "Y") {
                Open-InstallationPage "https://docs.docker.com/desktop/install/windows-install/"
            }
            
            return $false
        }
    }
}

# Function to check for WSL or Git Bash
function Test-BashEnvironment {
    Write-Step "Checking for Bash Environment"
    
    $gitBashPath = "C:\Program Files\Git\bin\bash.exe"
    $hasWsl = Test-CommandExists "wsl"
    $hasGitBash = Test-PathExists $gitBashPath
    
    if ($hasWsl) {
        Write-Host "Windows Subsystem for Linux (WSL) is installed." -ForegroundColor $SuccessColor
        return $true
    } elseif ($hasGitBash) {
        Write-Host "Git Bash is installed." -ForegroundColor $SuccessColor
        return $true
    } else {
        Write-Host "Neither WSL nor Git Bash was found." -ForegroundColor $WarningColor
        Write-Host "WSL or Git Bash is recommended for running the deployment script." -ForegroundColor $InformationColor
        
        $installBash = Read-Host "Would you like to install Git for Windows? (Y/n)"
        if ($installBash -eq "" -or $installBash -eq "y" -or $installBash -eq "Y") {
            Open-InstallationPage "https://gitforwindows.org/"
        }
        
        return $false
    }
}

# Function to check required directories exist
function Ensure-RequiredDirectories {
    Write-Step "Checking Required Directories"
    
    $directories = @(
        "storage",
        "storage/originals",
        "docker"
    )
    
    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            Write-Host "Creating directory: $dir" -ForegroundColor $InformationColor
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        } else {
            Write-Host "Directory exists: $dir" -ForegroundColor $SuccessColor
        }
    }
}

# Function to ensure docker-compose.prod.yml exists
function Ensure-DockerCompose {
    Write-Step "Checking Docker Compose Configuration"
    
    $composePath = "docker/docker-compose.prod.yml"
    if (-not (Test-Path $composePath)) {
        Write-Host "Creating a sample docker-compose.prod.yml file..." -ForegroundColor $InformationColor
        
        $composeContent = @"
version: '3.5'

services:
  photoprism:
    image: photoprism:latest
    container_name: photoprism_app
    restart: unless-stopped
    ports:
      - "2342:2342"
    environment:
      PHOTOPRISM_UID: "1000"
      PHOTOPRISM_GID: "1000"
      PHOTOPRISM_ADMIN_USER: "admin"
      PHOTOPRISM_ADMIN_PASSWORD: "photoprism"
      PHOTOPRISM_SITE_URL: "http://localhost:2342/"
    volumes:
      - ./storage:/photoprism/storage
      - ./originals:/photoprism/storage/originals
"@

        $composeContent | Set-Content -Path $composePath
        Write-Host "Created sample docker-compose.prod.yml at $composePath" -ForegroundColor $SuccessColor
    } else {
        Write-Host "Docker Compose file exists: $composePath" -ForegroundColor $SuccessColor
    }
}

# Function to check or create .env.prod file
function Ensure-EnvironmentFile {
    Write-Step "Checking Environment Configuration"
    
    $envPath = "docker/.env.prod"
    if (-not (Test-Path $envPath)) {
        Write-Host "Creating a sample .env.prod file..." -ForegroundColor $InformationColor
        
        $envContent = @"
# PhotoPrism Environment Configuration

# Admin user credentials
PHOTOPRISM_ADMIN_USER=admin
PHOTOPRISM_ADMIN_PASSWORD=photoprism

# Site configuration
PHOTOPRISM_SITE_URL=http://localhost:2342/
PHOTOPRISM_SITE_CAPTION="AI-Powered Photos App"
PHOTOPRISM_SITE_DESCRIPTION="Tags and finds pictures automatically!"
PHOTOPRISM_SITE_AUTHOR="@photoprism_app"

# Storage paths
PHOTOPRISM_ASSETS_PATH=/photoprism/assets
PHOTOPRISM_STORAGE_PATH=/photoprism/storage
PHOTOPRISM_ORIGINALS_PATH=/photoprism/storage/originals
PHOTOPRISM_IMPORT_PATH=/photoprism/storage/import
PHOTOPRISM_DISABLE_BACKUPS=false

# Performance settings
PHOTOPRISM_HTTP_MODE=release
PHOTOPRISM_DEBUG=false
PHOTOPRISM_THUMB_LIBRARY=auto
PHOTOPRISM_THUMB_FILTER=lanczos
PHOTOPRISM_THUMB_UNCACHED=true
PHOTOPRISM_THUMB_SIZE=1920
PHOTOPRISM_JPEG_SIZE=7680

# Video transcoding
PHOTOPRISM_FFMPEG_ENCODER=software
PHOTOPRISM_FFMPEG_SIZE=3840
PHOTOPRISM_FFMPEG_BITRATE=50
LIBVA_DRIVER_NAME=i965
"@

        $envContent | Set-Content -Path $envPath
        Write-Host "Created sample .env.prod at $envPath" -ForegroundColor $SuccessColor
    } else {
        Write-Host "Environment file exists: $envPath" -ForegroundColor $SuccessColor
    }
}

# Run environment checks
function Initialize-Environment {
    Write-Host "PhotoPrism Environment Setup" -ForegroundColor $InformationColor
    Write-Host "============================" -ForegroundColor $InformationColor
    
    $dockerInstalled = Test-DockerInstallation
    $bashAvailable = Test-BashEnvironment
    
    if (-not $dockerInstalled) {
        Write-Host "`nDockerを必ず先にインストールしてください! (Please install Docker first!)" -ForegroundColor $ErrorColor
        return $false
    }
    
    Ensure-RequiredDirectories
    Ensure-DockerCompose
    Ensure-EnvironmentFile
    
    Write-Host "`nEnvironment setup completed." -ForegroundColor $SuccessColor
    Write-Host "You can now run the deployment script:" -ForegroundColor $InformationColor
    
    if ($bashAvailable) {
        Write-Host "  - Using Git Bash: ./scripts/deploy-production.sh" -ForegroundColor $InformationColor
        Write-Host "  - Using PowerShell: .\Run-Deployment.ps1" -ForegroundColor $InformationColor
    } else {
        Write-Host "  - Using PowerShell: .\Run-Deployment.ps1" -ForegroundColor $InformationColor
    }
    
    return $true
}

# Execute the main function
Initialize-Environment
