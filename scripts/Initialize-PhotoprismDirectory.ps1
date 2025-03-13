<#
.SYNOPSIS
    Initializes the PhotoPrism directory structure and configuration files.
.DESCRIPTION
    Creates all necessary directories and configuration files for PhotoPrism deployment.
    Sets up appropriate security and default configurations.
.EXAMPLE
    .\Initialize-PhotoprismDirectory.ps1
.NOTES
    Author: PhotoPrism Team
#>

# Base directories
$BaseDir = "data"
$ConfigDir = "docker\config"
$ScriptDir = "scripts"
$SecretsDir = "docker\secrets"
$MonitoringDir = "docker\monitoring"
$NginxDir = "docker\nginx"
$TraefikDir = "docker\traefik"
$BackupDir = "docker\backup"
$ToolsDir = "tools"

# Create data directories with properly nested structure
$Directories = @(
    "$BaseDir\storage\cache",
    "$BaseDir\storage\sidecar",
    "$BaseDir\storage\config",
    "$BaseDir\storage\albums",
    "$BaseDir\storage\backups",
    "$BaseDir\storage\logs",
    "$BaseDir\originals",
    "$BaseDir\import",
    "$BaseDir\brains-models\faces",
    "$BaseDir\brains-models\objects",
    "$BaseDir\brains-models\scenes",
    "$BaseDir\brains-models\nsfw",
    "$BaseDir\mysql",
    "$ConfigDir\mariadb",
    "$ConfigDir\photoprism",
    "$ConfigDir\settings",
    "$MonitoringDir\prometheus",
    "$MonitoringDir\grafana\provisioning\dashboards",
    "$MonitoringDir\grafana\provisioning\datasources",
    "$MonitoringDir\loki",
    "$NginxDir\conf.d",
    "$NginxDir\ssl",
    "$TraefikDir\dynamic",
    "$BackupDir\scripts",
    "$BackupDir\logs",
    $SecretsDir
)

# Create all directories
foreach ($Dir in $Directories) {
    if (!(Test-Path $Dir)) {
        Write-Host "Creating directory: $Dir" -ForegroundColor Cyan
        New-Item -Path $Dir -ItemType Directory -Force | Out-Null
    }
}

# Create example secret files if they don't exist
$Secrets = @{
    "$SecretsDir\photoprism_admin_password.txt" = "change-me-now"
    "$SecretsDir\photoprism_db_password.txt"    = "change-me-now-db"
    "$SecretsDir\mariadb_root_password.txt"     = "change-me-now-root"
}

foreach ($Secret in $Secrets.Keys) {
    if (!(Test-Path $Secret)) {
        Write-Host "Creating secret file: $Secret" -ForegroundColor Yellow
        $Secrets[$Secret] | Out-File -FilePath $Secret -NoNewline -Encoding ascii
        # Set restrictive permissions
        icacls $Secret /inheritance:r
        icacls $Secret /grant:r "$($env:USERNAME):(F)"
    }
}

# Copy default config files if they don't exist
if (Test-Path "$ConfigDir\settings.json.example" -and !(Test-Path "$ConfigDir\settings.json")) {
    Write-Host "Copying settings.json from example" -ForegroundColor Cyan
    Copy-Item "$ConfigDir\settings.json.example" "$ConfigDir\settings.json"
}

Write-Host "Directory structure initialized successfully" -ForegroundColor Green
Write-Host "Remember to set proper passwords in $SecretsDir\*.txt files" -ForegroundColor Yellow
