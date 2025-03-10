<#
.SYNOPSIS
    Resets the BlackboxAI agent in VSCode to fix formatting issues
.DESCRIPTION
    This script clears cached data and restores default configuration for the BlackboxAI extension
#>

Write-Host "BlackboxAI Agent Reset Tool" -ForegroundColor Cyan
Write-Host "=========================" -ForegroundColor Cyan

# Configuration
$vscodeDir = "$env:APPDATA\Code"
$extensionsDir = "$vscodeDir\User\globalStorage"
$blackboxDir = Get-ChildItem -Path $extensionsDir -Filter "*blackbox*" -Directory -ErrorAction SilentlyContinue

# Step 1: Close VSCode if running
$vsCodeProcess = Get-Process -Name "Code" -ErrorAction SilentlyContinue
if ($vsCodeProcess) {
    Write-Host "VSCode is currently running. Please save your work and close VSCode." -ForegroundColor Yellow
    $continue = Read-Host "Continue with reset? (y/N)"
    if ($continue -ne "y") {
        Write-Host "Reset canceled." -ForegroundColor Red
        exit
    }
    
    Write-Host "Closing VSCode..." -ForegroundColor Yellow
    $vsCodeProcess | ForEach-Object { $_.CloseMainWindow() | Out-Null }
    Start-Sleep -Seconds 2
    
    # Force close if still running
    $vsCodeProcess = Get-Process -Name "Code" -ErrorAction SilentlyContinue
    if ($vsCodeProcess) {
        Write-Host "Forcing VSCode to close..." -ForegroundColor Red
        $vsCodeProcess | Stop-Process -Force
        Start-Sleep -Seconds 1
    }
}

# Step 2: Clear cache if BlackboxAI directory exists
if ($blackboxDir) {
    Write-Host "Found BlackboxAI extension storage: $($blackboxDir.FullName)" -ForegroundColor Green
    
    # Backup existing data
    $backupDir = "$vscodeDir\blackbox_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Write-Host "Backing up current data to $backupDir" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    Copy-Item -Path "$($blackboxDir.FullName)\*" -Destination $backupDir -Recurse -Force -ErrorAction SilentlyContinue
    
    # Clear cached sessions and state
    Write-Host "Clearing BlackboxAI cached sessions and state..." -ForegroundColor Yellow
    $sessionFiles = Get-ChildItem -Path $blackboxDir.FullName -Filter "*.json" -Recurse -File -ErrorAction SilentlyContinue
    foreach ($file in $sessionFiles) {
        Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
    }
    
    # Create default configuration if needed
    $configFile = "$($blackboxDir.FullName)\config.json"
    if (-not (Test-Path $configFile)) {
        Write-Host "Creating default configuration..." -ForegroundColor Yellow
        $defaultConfig = @{
            version = "1.0"
            settings = @{
                defaultFormat = "text"
                enableLogging = $true
                useMarkdown = $true
            }
        } | ConvertTo-Json -Depth 3
        
        $defaultConfig | Out-File -FilePath $configFile -Encoding UTF8
    }
} else {
    Write-Host "BlackboxAI extension storage not found. Please ensure the extension is installed." -ForegroundColor Red
}

# Step 3: Clear VSCode cache
Write-Host "Clearing VSCode workspace storage..." -ForegroundColor Yellow
$cachePaths = @(
    "$vscodeDir\Cache",
    "$vscodeDir\CachedData",
    "$vscodeDir\Code Cache"
)

foreach ($path in $cachePaths) {
    if (Test-Path $path) {
        Get-ChildItem -Path $path -File -Recurse -ErrorAction SilentlyContinue | 
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`nReset completed successfully!" -ForegroundColor Green
Write-Host "Please restart VSCode and the BlackboxAI extension should be reset to default state." -ForegroundColor Cyan
Write-Host "If you continue to experience issues, consider reinstalling the extension." -ForegroundColor Cyan

# Offer to restart VSCode
$restart = Read-Host "Would you like to restart VSCode now? (Y/n)"
if ($restart -eq "" -or $restart -eq "y" -or $restart -eq "Y") {
    Write-Host "Starting VSCode..." -ForegroundColor Green
    Start-Process "code"
}
