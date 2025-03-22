<#
.SYNOPSIS
    Wrapper for Docker commands to avoid PowerShell parsing issues
.DESCRIPTION
    This script passes through Docker commands but handles the output safely
    to prevent PowerShell from trying to parse Docker's output formatting
.EXAMPLE
    .\docker-run.ps1 build -t photoprism2 .
#>

param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$DockerArgs
)

# Set PowerShell to not interpret output
$ErrorActionPreference = "SilentlyContinue"

# Join the arguments into a command
$dockerCommand = "docker $($DockerArgs -join ' ')"
Write-Host "Executing: $dockerCommand" -ForegroundColor Cyan

# Execute the command, capturing and printing output to avoid parsing issues
$process = Start-Process -FilePath "docker" -ArgumentList $DockerArgs -NoNewWindow -PassThru -Wait

if ($process.ExitCode -eq 0) {
    Write-Host "Command completed successfully" -ForegroundColor Green
} else {
    Write-Host "Command failed with exit code $($process.ExitCode)" -ForegroundColor Red
}
