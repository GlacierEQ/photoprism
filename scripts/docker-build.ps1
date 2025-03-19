<#
.SYNOPSIS
    Advanced Docker Build Script for Windows
.DESCRIPTION
    This PowerShell script implements best practices for building Docker images on Windows
.PARAMETER Tag
    Image tag (default: latest)
.PARAMETER File
    Path to Dockerfile (default: ./Dockerfile)
.PARAMETER Platform
    Build platform (default: linux/amd64)
.PARAMETER NoCache
    Disable build cache
.PARAMETER BuildArg
    Add build arguments (can be used multiple times)
.EXAMPLE
    .\docker-build.ps1 -Tag v1.0.0 -BuildArg "NODE_ENV=production"
.NOTES
    Author: PhotoPrism2 Team
    Version: 1.0
#>

param (
    [Parameter(Alias = "t")]
    [string]$Tag = "latest",
    
    [Parameter(Alias = "f")]
    [string]$File = "./Dockerfile",
    
    [string]$Platform = "linux/amd64",
    
    [switch]$NoCache,
    
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$BuildArg
)

# Configuration
$IMAGE_NAME = if ($env:IMAGE_NAME) { $env:IMAGE_NAME } else { "photoprism2" }
$BUILD_CONTEXT = "."

# Display banner
Write-Host "`n🐳 PhotoPrism2 Docker Build"
Write-Host "==========================`n"

# Check if Docker daemon is running
try {
    $null = docker info
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Docker daemon is not running!" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "❌ Docker daemon is not running!" -ForegroundColor Red
    exit 1
}

# Check if Dockerfile exists
if (-not (Test-Path $File)) {
    Write-Host "❌ Dockerfile not found at $File" -ForegroundColor Red
    exit 1
}

# Prepare build arguments
$buildArgsString = ""
if ($BuildArg) {
    foreach ($arg in $BuildArg) {
        $buildArgsString += " --build-arg $arg"
    }
}

# Prepare cache options
$noCacheOption = if ($NoCache) { "--no-cache" } else { "" }

# Log build information
Write-Host "📦 Building $IMAGE_NAME`:$Tag"
Write-Host "📄 Using Dockerfile: $File"
Write-Host "🖥️ Platform: $Platform`n"

# Prepare the build command
$buildCommand = "docker buildx build " +
               "$noCacheOption " +
               "$buildArgsString " +
               "--platform $Platform " +
               "--file $File " +
               "--tag ""$IMAGE_NAME`:$Tag"" " +
               "--build-context app=$BUILD_CONTEXT " +
               "--progress=plain " +
               "--label ""org.opencontainers.image.created=$(Get-Date -Format 'o')"" " +
               "--label ""org.opencontainers.image.version=$Tag"" " +
               "$BUILD_CONTEXT"

# Execute the build command
Write-Host "Executing build command:`n$buildCommand`n" -ForegroundColor Yellow
Invoke-Expression $buildCommand

# Check if build was successful
if ($LASTEXITCODE -eq 0) {
    Write-Host "`n✅ Build completed successfully!" -ForegroundColor Green
    
    # Get image size
    $imageSize = docker image inspect "$IMAGE_NAME`:$Tag" --format "{{.Size}}"
    $imageSizeMB = [math]::Round($imageSize / 1MB, 2)
    Write-Host "Image details:"
    Write-Host "Size: $imageSizeMB MB"
    
    Write-Host "`nRun with: docker run -d --name photoprism2 $IMAGE_NAME`:$Tag"
}
else {
    Write-Host "`n❌ Build failed!" -ForegroundColor Red
}
