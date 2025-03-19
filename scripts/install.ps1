<#
.SYNOPSIS
    PhotoPrism2 Docker Installation and Setup Script for Windows
.DESCRIPTION
    This PowerShell script provides commands for installing Docker and setting up PhotoPrism2 on Windows.
    It handles Docker Desktop installation checks, directory setup, and environment configuration.
.NOTES
    Author: PhotoPrism2 Team
    Version: 1.0
#>

# Configuration variables (can be overridden via environment variables)
$ErrorActionPreference = "Stop"
$LogDir = if ($env:LOG_DIR) { $env:LOG_DIR } else { ".\logs" }
$InstallDir = Get-Location
$TimeStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile = Join-Path -Path $LogDir -ChildPath "install-$TimeStamp.log"

# Create log directory if it doesn't exist
if (-not (Test-Path -Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# Log function
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage
}

# Error handler function
function Handle-Error {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)
    Write-Log "ERROR: $($ErrorRecord.Exception.Message)"
    Write-Log "Installation failed at line $($ErrorRecord.InvocationInfo.ScriptLineNumber)"
    exit 1
}

# Set error handler
trap {
    Handle-Error $_
    continue
}

# Display welcome message
Write-Log "==========================================="
Write-Log "     PhotoPrism2 Docker Installation       "
Write-Log "==========================================="
Write-Log ""

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Log "Warning: This script should be run as Administrator for full functionality."
    Write-Log "Some operations might fail without administrator privileges."
    $continue = Read-Host "Continue anyway? (y/n)"
    if ($continue -ne "y") {
        Write-Log "Installation aborted. Please restart as Administrator."
        exit 0
    }
}

# Function to verify Docker installation
function Verify-Docker {
    Write-Log "Verifying Docker installation..."
    
    try {
        # Check if docker command is available
        if (-not (Get-Command "docker.exe" -ErrorAction SilentlyContinue)) {
            Write-Log "Docker command not found. Please install Docker Desktop first."
            return $false
        }
        
        # Check if Docker daemon is running
        $dockerInfo = docker info 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Docker daemon is not running. Please start Docker Desktop."
            return $false
        }
        
        # Check if Docker is running in Windows container mode
        if ($dockerInfo -match "windows") {
            Write-Log "⚠️ Docker is running in Windows container mode!"
            Write-Log "Please switch to Linux containers in Docker Desktop settings."
            return $false
        }
        
        Write-Log "✅ Docker is installed and running correctly."
        docker version
        return $true
    }
    catch {
        Write-Log "Error checking Docker: $_"
        return $false
    }
}

# Function to install Docker Desktop
function Install-DockerDesktop {
    Write-Log "Starting Docker Desktop installation process..."
    
    Write-Log "For Windows, you need to install Docker Desktop manually:"
    Write-Log "1. Download Docker Desktop from: https://www.docker.com/products/docker-desktop"
    Write-Log "2. Install Docker Desktop and launch it"
    Write-Log "3. Ensure WSL2 is enabled"
    Write-Log "4. In Docker Desktop settings:"
    Write-Log "   - Ensure 'Use the WSL2 based engine' is selected"
    Write-Log "   - Give Docker at least 4GB of RAM in Resources > Advanced"
    Write-Log ""
    
    $dockerInstalled = Read-Host "Have you installed Docker Desktop? (y/n)"
    if ($dockerInstalled -ne "y") {
        Write-Log "Please install Docker Desktop first and run this script again."
        exit 0
    }
    
    # Check if Docker Desktop is running
    if (-not (Verify-Docker)) {
        Write-Log "Docker Desktop is not running or not properly configured."
        $startDocker = Read-Host "Do you want to try starting Docker Desktop? (y/n)"
        
        if ($startDocker -eq "y") {
            Write-Log "Attempting to start Docker Desktop..."
            Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
            
            Write-Log "Waiting for Docker to start (this may take a minute)..."
            $attempts = 0
            $maxAttempts = 30
            
            while ($attempts -lt $maxAttempts) {
                Start-Sleep -Seconds 5
                $attempts++
                Write-Host "." -NoNewline
                
                try {
                    $null = docker info
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "`nDocker Desktop started successfully!"
                        return $true
                    }
                }
                catch { }
            }
            
            Write-Log "`nTimeout waiting for Docker to start. Please start Docker Desktop manually."
            return $false
        }
        else {
            Write-Log "Please start Docker Desktop manually and run this script again."
            return $false
        }
    }
    
    return $true
}

# Function to configure PhotoPrism environment
function Configure-PhotoPrism {
    Write-Log "Configuring PhotoPrism2 environment..."
    
    # Ensure required directories exist
    Write-Log "Creating required directories..."
    $directories = @(
        "docker\secrets",
        "docker\config\mariadb",
        "docker\config\postgres",
        "docker\traefik",
        "data\mysql",
        "data\storage"
    )
    
    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Log "Created directory: $dir"
        }
    }
    
    # Generate initial configuration files
    Write-Log "Generating configuration files..."
    
    # Create secret files if they don't exist
    if (-not (Test-Path "docker\secrets\photoprism_admin_password.txt")) {
        Write-Log "Setting up admin password..."
        $adminPwd = Read-Host "Enter admin password (default: admin)" -AsSecureString
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminPwd)
        $plainAdminPwd = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        
        if ([string]::IsNullOrEmpty($plainAdminPwd)) {
            $plainAdminPwd = "admin"
        }
        
        Set-Content -Path "docker\secrets\photoprism_admin_password.txt" -Value $plainAdminPwd -NoNewline
        Write-Log "Admin password file created."
    }
    
    if (-not (Test-Path "docker\secrets\photoprism_db_password.txt")) {
        Write-Log "Setting up database password..."
        $dbPwd = Read-Host "Enter database password (default: photoprism)" -AsSecureString
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($dbPwd)
        $plainDbPwd = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        
        if ([string]::IsNullOrEmpty($plainDbPwd)) {
            $plainDbPwd = "photoprism"
        }
        
        Set-Content -Path "docker\secrets\photoprism_db_password.txt" -Value $plainDbPwd -NoNewline
        Write-Log "Database password file created."
    }
    
    if (-not (Test-Path "docker\secrets\mariadb_root_password.txt")) {
        Write-Log "Setting up MariaDB root password..."
        $mariadbPwd = Read-Host "Enter MariaDB root password (default: root)" -AsSecureString
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($mariadbPwd)
        $plainMariadbPwd = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        
        if ([string]::IsNullOrEmpty($plainMariadbPwd)) {
            $plainMariadbPwd = "root"
        }
        
        Set-Content -Path "docker\secrets\mariadb_root_password.txt" -Value $plainMariadbPwd -NoNewline
        Write-Log "MariaDB root password file created."
    }
}

# Function to fix Docker Compose files
function Fix-DockerComposeFiles {
    Write-Log "Fixing Docker Compose file conflicts..."
    
    if (Test-Path "compose.yaml") {
        Write-Log "- Removing obsolete compose.yaml"
        Remove-Item "compose.yaml" -Force
    }
    
    if (Test-Path "docker-compose.override.yml") {
        Write-Log "- Updating docker-compose.override.yml format"
        $content = Get-Content "docker-compose.override.yml" | Where-Object { $_ -notmatch '^version:' }
        Set-Content "docker-compose.override.yml" -Value $content
    }
    
    # Check Docker context
    Write-Log "Checking Docker context..."
    $dockerContext = docker context ls --format "{{.Current}} {{.Name}}" | Where-Object { $_ -match "^\* " }
    
    if ($dockerContext -notmatch "desktop-linux") {
        Write-Log "- Setting Docker context to desktop-linux"
        docker context use desktop-linux 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Log "⚠️ Could not set Docker context to desktop-linux"
        }
    }
}

# Function to pull required Docker images
function Pull-DockerImages {
    Write-Log "Pulling required Docker images..."
    
    try {
        Write-Log "- Pulling Traefik image"
        docker pull traefik:v2.10
        if ($LASTEXITCODE -ne 0) {
            Write-Log "⚠️ Failed to pull Traefik image"
        }
        
        Write-Log "- Pulling MariaDB image"
        docker pull mariadb:10.11
        if ($LASTEXITCODE -ne 0) {
            Write-Log "⚠️ Failed to pull MariaDB image"
        }
        
        Write-Log "- Pulling PhotoPrism image"
        docker pull photoprism/photoprism:latest
        if ($LASTEXITCODE -ne 0) {
            Write-Log "⚠️ Failed to pull PhotoPrism image"
        }
    }
    catch {
        Write-Log "Error pulling Docker images: $_"
    }
}

# Main installation process
try {
    # Check and install Docker Desktop if needed
    $dockerReady = Install-DockerDesktop
    
    if (-not $dockerReady) {
        Write-Log "Docker Desktop is not ready. Please fix the issues and run this script again."
        exit 1
    }
    
    # Configure PhotoPrism environment
    Configure-PhotoPrism
    
    # Fix Docker Compose files
    Fix-DockerComposeFiles
    
    # Pull required Docker images
    Pull-DockerImages
    
    # Installation complete
    Write-Log "Installation completed successfully!"
    Write-Log "To start PhotoPrism2, run:"
    Write-Log "  docker-compose up -d"
    Write-Log ""
    Write-Log "To access PhotoPrism2:"
    Write-Log "  http://localhost:2342/"
    Write-Log "  Username: admin"
    Write-Log "  Password: (check docker\secrets\photoprism_admin_password.txt)"
    Write-Log ""
    Write-Log "For best practice Docker builds, run the PowerShell build script:"
    Write-Log "  .\scripts\docker-build.ps1"
    Write-Log ""
    Write-Log "Installation log saved to: $LogFile"
    
}
catch {
    Handle-Error $_
}
