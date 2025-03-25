#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter()]
    [string]$BuildType = "develop",
    [Parameter()]
    [string]$OutputName = "photoprism"
)

$ErrorActionPreference = "Stop"
$BuildDate = Get-Date -Format "yyMMdd"
$BuildVersion = git describe --always
$BuildTag = "$BuildDate-$BuildVersion"
$BuildOS = "Windows"
$BuildArch = if ([Environment]::Is64BitOperatingSystem) { "AMD64" } else { "386" }
$BuildId = "$BuildTag-$BuildOS-$BuildArch"

# Logging functions
function Write-BuildLog {
    param([string]$Message, [string]$Level = "Info")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    switch ($Level) {
        "Error" { Write-Host "[$timestamp] ERROR: $Message" -ForegroundColor Red }
        "Warning" { Write-Host "[$timestamp] WARN: $Message" -ForegroundColor Yellow }
        default { Write-Host "[$timestamp] INFO: $Message" -ForegroundColor Cyan }
    }
}

# Check prerequisites
function Test-BuildPrerequisites {
    try {
        $goVersion = go version
        Write-BuildLog "Using $goVersion"

        $nodeVersion = node --version
        Write-BuildLog "Using Node.js $nodeVersion"

        $npmVersion = npm --version
        Write-BuildLog "Using npm $npmVersion"
    }
    catch {
        Write-BuildLog "Missing build dependencies. Please ensure Go, Node.js and npm are installed." "Error"
        exit 1
    }
}

# Configure build based on type
function Set-BuildConfig {
    switch ($BuildType) {
        "develop" {
            $script:BuildTags = "debug,develop,brains"
            $script:BuildLdFlags = "-X main.version=${BuildId}-DEVELOP"
        }
        "race" {
            $script:BuildTags = "debug,brains"
            $script:BuildLdFlags = "-X main.version=${BuildId}-RACE"
        }
        "debug" {
            $script:BuildTags = "debug,brains"
            $script:BuildLdFlags = "-s -w -X main.version=${BuildId}"
            $script:OutputName += "-DEBUG"
        }
        default {
            $script:BuildTags = "brains"
            $script:BuildLdFlags = "-s -w -X main.version=${BuildId}"
        }
    }

    Write-BuildLog "Build configuration:"
    Write-BuildLog "  Build Type: $BuildType"
    Write-BuildLog "  Build Tags: $BuildTags"
    Write-BuildLog "  Build ID: $BuildId"
    Write-BuildLog "  Output Name: $OutputName"
}

# Build the application
function Invoke-Build {
    try {
        Write-BuildLog "Building project..."
        $buildCmd = "go build -tags=`"$BuildTags`" -ldflags `"$BuildLdFlags`" -o `"$OutputName.exe`" cmd/photoprism/photoprism.go"

        Write-BuildLog "Executing: $buildCmd"
        Invoke-Expression $buildCmd

        if ($LASTEXITCODE -ne 0) {
            throw "Build failed with exit code $LASTEXITCODE"
        }

        Write-BuildLog "Build completed successfully"
    }
    catch {
        Write-BuildLog $_.Exception.Message "Error"
        exit 1
    }
}

# Build Docker image
function Invoke-DockerBuild {
    try {
        Write-BuildLog "Building Docker image..."

        # Format build date for Docker tag
        $buildDate = Get-Date -Format "yyMMdd"

        $dockerArgs = @(
            "build",
            "-t", "photoprism2:latest",
            "--build-arg", "PHOTOPRISM_VERSION=$buildDate",
            "--build-arg", "GO_VERSION=1.21",
            "--build-arg", "NODE_VERSION=18",
            "."
        )

        Write-BuildLog "Docker build command: docker $($dockerArgs -join ' ')"
        & docker $dockerArgs

        if ($LASTEXITCODE -ne 0) {
            throw "Docker build failed with exit code $LASTEXITCODE"
        }

        Write-BuildLog "Docker image built successfully"
    }
    catch {
        Write-BuildLog $_.Exception.Message "Error"
        exit 1
    }
}

# Verify Docker image
function Test-DockerImage {
    try {
        Write-BuildLog "Verifying Docker image..."

        # Run verification script
        $verifyScript = Join-Path $PSScriptRoot "verify-docker.sh"
        if (Test-Path $verifyScript) {
            bash $verifyScript
            if ($LASTEXITCODE -ne 0) {
                throw "Image verification failed"
            }
        }
        else {
            Write-BuildLog "Verification script not found at: $verifyScript" "Warning"
        }
    }
    catch {
        Write-BuildLog $_.Exception.Message "Error"
        exit 1
    }
}

# Main execution flow
try {
    Write-BuildLog "Starting development build for PhotoPrism"
    Test-BuildPrerequisites
    Set-BuildConfig
    Invoke-Build
    Invoke-DockerBuild
    Test-DockerImage # Add verification step
}
catch {
    Write-BuildLog $_.Exception.Message "Error"
    exit 1
}
