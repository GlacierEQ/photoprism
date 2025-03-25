# Initialize PhotoPrism secrets
$ErrorActionPreference = "Stop"

# Ensure secrets directory exists
$secretsDir = "..\secrets"
New-Item -Path $secretsDir -ItemType Directory -Force | Out-Null

# Function to generate random password
function Get-RandomPassword {
    param(
        [int]$length = 16,
        [switch]$includeSpecial
    )
    $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    if ($includeSpecial) {
        $chars += "!@#$%^&*"
    }
    return -join ((1..$length) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
}

# Create secret files if they don't exist
$secrets = @{
    "db_root_password.txt" = (Get-RandomPassword -length 32 -includeSpecial)
    "db_password.txt" = (Get-RandomPassword -length 24 -includeSpecial)
    "photoprism_admin_password.txt" = (Get-RandomPassword -length 16)
}

foreach ($secret in $secrets.GetEnumerator()) {
    $filePath = Join-Path $secretsDir $secret.Key
    if (-not (Test-Path $filePath)) {
        $secret.Value | Out-File -FilePath $filePath -NoNewline -Encoding UTF8
        Write-Host "Created secret file: $($secret.Key)"
    }
}

Write-Host "Secrets initialized successfully!"
