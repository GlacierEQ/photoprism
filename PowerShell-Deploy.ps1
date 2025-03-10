<#
.SYNOPSIS
    PowerShell script to build and deploy PhotoPrism with proper line ending handling
.DESCRIPTION
    This script handles line ending conversion before building the Docker image
#>

# Set error action preference
$ErrorActionPreference = "Stop"

Write-Host "PhotoPrism Docker Deployment" -ForegroundColor Cyan
Write-Host "==========================" -ForegroundColor Cyan

# Create the line endings fix script if it doesn't exist
$fixScriptPath = ".\scripts\fix-line-endings.sh"
if (-not (Test-Path $fixScriptPath)) {
    Write-Host "Creating line endings fix script..." -ForegroundColor Yellow
    $fixScriptContent = @'
#!/bin/sh
# This script fixes line endings in bash scripts
# It converts CRLF line endings to LF

echo "Fixing line endings in shell scripts..."

# Fix the main deployment script
sed -i 's/\r$//' /app/scripts/deploy-production.sh
echo "Fixed deploy-production.sh"

# Fix any other scripts
find /app/scripts -type f -name "*.sh" -exec sed -i 's/\r$//' {} \;
echo "Fixed all .sh scripts in /app/scripts"

# Fix the start script
if [ -f /app/start.sh ]; then
  sed -i 's/\r$//' /app/start.sh
  echo "Fixed start.sh"
fi

echo "Line ending fixes completed."
'@
    
    # Create the directory if it doesn't exist
    if (-not (Test-Path ".\scripts")) {
        New-Item -Path ".\scripts" -ItemType Directory | Out-Null
    }
    
    # Write the content with LF line endings
    $fixScriptContent | Set-Content -Path $fixScriptPath -NoNewline
    
    # Convert to LF line endings
    $content = [System.IO.File]::ReadAllText($fixScriptPath)
    [System.IO.File]::WriteAllText($fixScriptPath, $content.Replace("`r`n", "`n"))
    
    Write-Host "Created fix-line-endings.sh with LF line endings" -ForegroundColor Green
}

# Build the Docker image
Write-Host "Building Docker image..." -ForegroundColor Cyan
docker build -t photoprism:latest -f Dockerfile .

# Check if build was successful
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Docker build failed" -ForegroundColor Red
    exit $LASTEXITCODE
}

# Run the container
Write-Host "Running PhotoPrism container..." -ForegroundColor Cyan

# Check if container already exists
$containerExists = docker ps -a --filter "name=photoprism_app" --format "{{.Names}}" | Where-Object { $_ -eq "photoprism_app" }
if ($containerExists) {
    Write-Host "Container 'photoprism_app' already exists, removing it..." -ForegroundColor Yellow
    docker rm -f photoprism_app
}

# Run the container
docker run -d -p 2342:2342 -p 3000:3000 `
  -v "${PWD}/storage:/photoprism/storage" `
  -v "${PWD}/originals:/photoprism/storage/originals" `
  --name photoprism_app `
  photoprism:latest

# Check if container started successfully
if ($LASTEXITCODE -eq 0) {
    Write-Host "PhotoPrism container started successfully!" -ForegroundColor Green
    Write-Host "Access the application at: http://localhost:2342" -ForegroundColor Cyan
    
    # Open browser
    $openBrowser = Read-Host "Would you like to open the application in your browser? (Y/n)"
    if ($openBrowser -eq "" -or $openBrowser -eq "y" -or $openBrowser -eq "Y") {
        Start-Process "http://localhost:2342"
    }
} else {
    Write-Host "Error: Failed to start container" -ForegroundColor Red
}
