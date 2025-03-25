#Requires -Version 7.0

$ErrorActionPreference = "Stop"

# Clean previous build artifacts
Remove-Item -Force -ErrorAction SilentlyContinue `
    photoprism.exe,
    go.sum

# Reset modules
Write-Host "Cleaning Go modules..."
go clean -modcache
go mod tidy

# Run build
Write-Host "Building project..."
./scripts/build-dev.ps1
