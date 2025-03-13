<#
.SYNOPSIS
    Enhanced Ninja Team Status Reporter - PowerShell Edition
.DESCRIPTION
    Provides real-time monitoring of ninja team deployments with hardware monitoring support
.PARAMETER TeamSize
    Number of team members to monitor (default: 12)
.PARAMETER RefreshInterval
    Seconds between status updates (default: 5 seconds)
.PARAMETER BuildDir
    Directory where build artifacts are stored (default: ./build/ninja)
.PARAMETER OutputFormat
    Format for output: text, json, csv (default: text)
.PARAMETER BenchmarkEnabled
    Enable performance benchmarking (default: $false)
.PARAMETER ConfigFile
    Path to configuration file (optional)
.EXAMPLE
    .\Ninja-TeamStatusMonitor.ps1 -TeamSize 12 -RefreshInterval 3
.NOTES
    Version: 2.0.0
#>

param (
    [Parameter(Position = 0)]
    [int]$TeamSize = 12,

    [Parameter(Position = 1)]
    [int]$RefreshInterval = 5,

    [Parameter()]
    [string]$BuildDir = $null,

    [Parameter()]
    [ValidateSet("text", "json", "csv")]
    [string]$OutputFormat = "text",

    [Parameter()]
    [switch]$BenchmarkEnabled = $false,

    [Parameter()]
    [string]$ConfigFile = $null,

    [Parameter()]
    [ValidateSet("DEBUG", "INFO", "WARN", "ERROR", "FATAL")]
    [string]$LogLevel = "INFO"
)

# Error handling configuration
$ErrorActionPreference = "Stop"

# Setup script environment
$ScriptDir = $PSScriptRoot
if (!$ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)

# Initialize configuration
if (!$BuildDir) {
    $BuildDir = Join-Path -Path $ProjectRoot -ChildPath "build\ninja"
}

$LogFile = Join-Path -Path $BuildDir -ChildPath "logs\status-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$DeploymentStatusFile = Join-Path -Path $BuildDir -ChildPath "deployment-status.json"

# Create directories if they don't exist
if (!(Test-Path (Split-Path -Parent $LogFile))) {
    New-Item -Path (Split-Path -Parent $LogFile) -ItemType Directory -Force | Out-Null
}

# Initialize runtime variables
$Global:PerfMetrics = @{}
$Global:StartTime = Get-Date

# Colors for output
$Colors = @{
    Red     = "Red"
    Green   = "Green"
    Yellow  = "Yellow"
    Blue    = "Cyan" # PowerShell "Cyan" is closer to bash "Blue"
    Cyan    = "Cyan"
    Magenta = "Magenta"
    White   = "White"
    Gray    = "Gray"
    Bold    = "White"
}

# Map log levels to numeric values
$LogLevels = @{
    "DEBUG" = 0
    "INFO"  = 1
    "WARN"  = 2
    "ERROR" = 3
    "FATAL" = 4
}

# Get current log level numeric value
$CurrentLogLevel = $LogLevels[$LogLevel]

# Load configuration file if specified
if ($ConfigFile -and (Test-Path $ConfigFile)) {
    try {
        $config = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json
        if ($config.team_size) { $TeamSize = $config.team_size }
        if ($config.refresh_interval) { $RefreshInterval = $config.refresh_interval }
        if ($config.build_dir) { $BuildDir = $config.build_dir }
        if ($config.log_level) { $LogLevel = $config.log_level }
        Write-Host "Loaded configuration from $ConfigFile" -ForegroundColor $Colors.Green
    }
    catch {
        Write-Host "Error loading configuration: $_" -ForegroundColor $Colors.Red
    }
}

#region Helper Functions

# Write to log with timestamp and level
function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $levelNum = $LogLevels[$Level]

    if ($levelNum -ge $CurrentLogLevel) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

        # Select color based on level
        $color = switch ($Level) {
            "DEBUG" { $Colors.Gray }
            "INFO" { $Colors.Green }
            "WARN" { $Colors.Yellow }
            "ERROR" { $Colors.Red }
            "FATAL" { $Colors.Red }
            default { $Colors.White }
        }

        # Output to console
        Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color

        # Output to log file
        if ($LogFile) {
            "[$timestamp] [$Level] $Message" | Out-File -FilePath $LogFile -Append -Encoding utf8
        }
    }
}

function Write-Debug2 { param([string]$Message) Write-Log -Level "DEBUG" -Message $Message }
function Write-Info { param([string]$Message) Write-Log -Level "INFO"  -Message $Message }
function Write-Warning2 { param([string]$Message) Write-Log -Level "WARN"  -Message $Message }
function Write-Error2 { param([string]$Message) Write-Log -Level "ERROR" -Message $Message }
function Write-Fatal { param([string]$Message) Write-Log -Level "FATAL" -Message $Message; exit 1 }

# Function to measure execution time of commands (for benchmarking)
function Measure-ExecutionTime {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock
    )

    if ($BenchmarkEnabled) {
        $startTime = Get-Date
        & $ScriptBlock
        $endTime = Get-Date
        $executionTime = ($endTime - $startTime).TotalSeconds
        $Global:PerfMetrics[$Name] = $executionTime
        Write-Debug2 "Benchmark: $Name took $executionTime seconds"
    }
    else {
        & $ScriptBlock
    }
}

# Read JSON file with error handling
function Get-JsonContent {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter()]
        $DefaultValue = $null
    )

    if (!(Test-Path $FilePath)) {
        return $DefaultValue
    }

    try {
        $json = Get-Content -Path $FilePath -Raw | ConvertFrom-Json
        return $json
    }
    catch {
        Write-Debug2 "Error reading JSON from $FilePath: $_"
        return $DefaultValue
    }
}

# Get specific value from JSON object with default
function Get-JsonValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName,

        [Parameter()]
        $DefaultValue = $null
    )

    $json = Get-JsonContent -FilePath $FilePath

    if ($null -eq $json) {
        return $DefaultValue
    }

    try {
        $value = $json.$PropertyName
        if ($null -eq $value) {
            return $DefaultValue
        }
        return $value
    }
    catch {
        Write-Debug2 "Error extracting $PropertyName from JSON: $_"
        return $DefaultValue
    }
}

# Print performance metrics
function Show-PerformanceMetrics {
    if (!$BenchmarkEnabled) {
        return
    }

    $totalTime = (Get-Date) - $Global:StartTime

    Write-Host "===== PERFORMANCE METRICS =====" -ForegroundColor $Colors.Cyan

    foreach ($name in $Global:PerfMetrics.Keys) {
        $value = $Global:PerfMetrics[$name]
        Write-Host ("{0,-30}: {1,10:F3} seconds" -f $name, $value)
    }

    Write-Host ("{0,-30}: {1,10:F3} seconds" -f "Total execution time", $totalTime.TotalSeconds)
}

#endregion

#region Hardware Monitoring

# Check GPU status
function Get-GpuStatus {
    Write-Debug2 "Checking GPU status..."

    $gpuDetected = $false

    # NVIDIA GPU check
    if (Get-Command "nvidia-smi" -ErrorAction SilentlyContinue) {
        Write-Host "NVIDIA GPU Status:" -ForegroundColor $Colors.Bold

        try {
            $gpuInfo = nvidia-smi --query-gpu=index, name, temperature.gpu, utilization.gpu, memory.used, memory.total --format=csv, noheader

            foreach ($line in $gpuInfo -split "`n") {
                $parts = $line -split ',\s*'
                if ($parts.Count -ge 5) {
                    Write-Host "  GPU $($parts[0]): $($parts[1])"
                    Write-Host "    Temperature: $($parts[2])°C | Utilization: $($parts[3]) | Memory: $($parts[4]) / $($parts[5])"
                }
            }

            $gpuDetected = $true
        }
        catch {
            Write-Host "  Error retrieving NVIDIA GPU information: $_" -ForegroundColor $Colors.Red
        }
    }

    # AMD GPU check (Windows)
    if (-not $gpuDetected) {
        try {
            $gpus = Get-WmiObject Win32_VideoController -ErrorAction SilentlyContinue
            if ($gpus) {
                Write-Host "GPU Status:" -ForegroundColor $Colors.Bold
                foreach ($gpu in $gpus) {
                    Write-Host "  $($gpu.Name)"
                    Write-Host "    Driver Version: $($gpu.DriverVersion)"
                    Write-Host "    Video Mode: $($gpu.VideoModeDescription)"
                }
                $gpuDetected = $true
            }
        }
        catch {
            Write-Host "  Error retrieving Windows GPU information: $_" -ForegroundColor $Colors.Red
        }
    }

    if (-not $gpuDetected) {
        Write-Host "No GPU monitoring tools available or no GPU detected" -ForegroundColor $Colors.Yellow
    }

    return $gpuDetected
}

# Check for specialized hardware (NPU/TPU/etc)
function Get-SpecializedHardwareStatus {
    Write-Debug2 "Checking specialized hardware status..."

    $hardwareDetected = $false

    # Check for Windows ML acceleration
    try {
        if (Get-Command Get-WindowsOptionalFeature -ErrorAction SilentlyContinue) {
            $mlFeature = Get-WindowsOptionalFeature -Online -FeatureName "DirectML" -ErrorAction SilentlyContinue
            if ($mlFeature -and $mlFeature.State -eq "Enabled") {
                Write-Host "Windows ML Acceleration:" -ForegroundColor $Colors.Bold
                Write-Host "  DirectML is enabled for hardware acceleration"
                $hardwareDetected = $true
            }
        }
    }
    catch {
        Write-Debug2 "Error checking Windows ML: $_"
    }

    # Check for Intel Neural Compute Stick or similar devices
    try {
        $usbDevices = Get-WmiObject Win32_USBControllerDevice -ErrorAction SilentlyContinue | ForEach-Object { [wmi]($_.Dependent) }
        $aiDevices = $usbDevices | Where-Object { $_.Description -match "Neural|AI|TPU|VPU" }

        if ($aiDevices) {
            Write-Host "AI Accelerator Devices:" -ForegroundColor $Colors.Bold
            foreach ($device in $aiDevices) {
                Write-Host "  $($device.Description)"
                Write-Host "    Device ID: $($device.DeviceID)"
                $hardwareDetected = $true
            }
        }
    }
    catch {
        Write-Debug2 "Error checking USB devices: $_"
    }

    if (-not $hardwareDetected) {
        Write-Host "No specialized AI hardware detected" -ForegroundColor $Colors.Yellow
    }

    return $hardwareDetected
}

#endregion

#region System Status Functions

# Display system resource information
function Show-SystemResources {
    Write-Host "===== SYSTEM RESOURCES =====" -ForegroundColor $Colors.Cyan

    # CPU information
    Write-Host "CPU Usage:" -ForegroundColor $Colors.Bold
    try {
        $cpuLoad = (Get-WmiObject Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
        Write-Host "  Current Usage: $cpuLoad%"

        $cpuInfo = Get-WmiObject Win32_Processor | Select-Object -First 1
        Write-Host "  Processor: $($cpuInfo.Name)"
        Write-Host "  Cores/Threads: $($cpuInfo.NumberOfCores)/$($cpuInfo.NumberOfLogicalProcessors)"
    }
    catch {
        Write-Host "  Error retrieving CPU information: $_" -ForegroundColor $Colors.Red
    }

    # Memory information
    Write-Host "`nMemory Usage:" -ForegroundColor $Colors.Bold
    try {
        $computerSystem = Get-WmiObject Win32_ComputerSystem
        $totalMemoryGB = [math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 2)

        $osInfo = Get-WmiObject Win32_OperatingSystem
        $usedMemoryGB = [math]::Round(($totalMemoryGB - ($osInfo.FreePhysicalMemory / 1MB)), 2)
        $memoryUsagePercent = [math]::Round(($usedMemoryGB / $totalMemoryGB) * 100, 0)

        Write-Host "  Used: $usedMemoryGB GB of $totalMemoryGB GB ($memoryUsagePercent%)"
    }
    catch {
        Write-Host "  Error retrieving memory information: $_" -ForegroundColor $Colors.Red
    }

    # Disk information
    Write-Host "`nDisk Usage:" -ForegroundColor $Colors.Bold
    try {
        $diskDrives = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 -and $_.Size -gt 0 }
        foreach ($disk in $diskDrives) {
            $sizeGB = [math]::Round($disk.Size / 1GB, 2)
            $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
            $usedGB = [math]::Round($sizeGB - $freeGB, 2)
            $usedPercent = [math]::Round(($usedGB / $sizeGB) * 100, 0)

            Write-Host "  Drive $($disk.DeviceID): $usedGB GB used of $sizeGB GB ($usedPercent%)"
        }
    }
    catch {
        Write-Host "  Error retrieving disk information: $_" -ForegroundColor $Colors.Red
    }

    # GPU status
    Write-Host ""
    Get-GpuStatus

    # Specialized hardware status
    Write-Host ""
    Get-SpecializedHardwareStatus
}

# Display deployment status
function Show-DeploymentStatus {
    Write-Host "===== PHOTOPRISM NINJA TEAM STATUS REPORT =====" -ForegroundColor $Colors.Cyan
    Write-Host "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor $Colors.Cyan
    Write-Host ""

    # Display overall deployment status
    if (Test-Path $DeploymentStatusFile) {
        try {
            $status = Get-JsonValue -FilePath $DeploymentStatusFile -PropertyName "status" -DefaultValue "Unknown"
            $environment = Get-JsonValue -FilePath $DeploymentStatusFile -PropertyName "environment" -DefaultValue "Unknown"
            $timestamp = Get-JsonValue -FilePath $DeploymentStatusFile -PropertyName "timestamp" -DefaultValue "Unknown"

            # Set color based on status
            $statusColor = switch -Wildcard ($status) {
                "ready*" { $Colors.Green }
                "completed*" { $Colors.Green }
                "success*" { $Colors.Green }
                "deploye*" { $Colors.Blue }
                "in_progress*" { $Colors.Blue }
                "starting*" { $Colors.Blue }
                "failed*" { $Colors.Red }
                "error*" { $Colors.Red }
                default { $Colors.White }
            }

            Write-Host "Deployment Status: " -NoNewline
            Write-Host $status -ForegroundColor $statusColor
            Write-Host "Environment: $environment"
            Write-Host "Last Updated: $timestamp"
        }
        catch {
            Write-Warning2 "Error parsing deployment status: $_"
            Write-Host "Deployment Status: Unknown" -ForegroundColor $Colors.Yellow
        }
    }
    else {
        Write-Host "No deployment status found" -ForegroundColor $Colors.Yellow
    }
}

# Display team status information
function Show-TeamStatus {
    Write-Host "===== TEAM STATUS =====" -ForegroundColor $Colors.Cyan

    # Check if team directory exists
    $teamDir = Join-Path -Path $BuildDir -ChildPath "teams"
    if (!(Test-Path $teamDir)) {
        $teamDir = Join-Path -Path $BuildDir -ChildPath "team"
        if (!(Test-Path $teamDir)) {
            Write-Host "Team directory not found: $teamDir" -ForegroundColor $Colors.Yellow
            return
        }
    }

    # Display table header
    Write-Host ("{0,-8} {1,-15} {2,-15} {3,-15} {4,-25}" -f "TEAM ID", "STATUS", "COMPLETED", "FAILED", "CURRENT TASK")
    Write-Host ("-" * 80)

    # Track statistics
    $activeTeams = 0
    $completedTeams = 0
    $failedTeams = 0
    $totalCompleted = 0
    $totalFailed = 0

    # Check for team members or teams directory pattern
    $teamPattern = if (Test-Path (Join-Path -Path $teamDir -ChildPath "team-1")) { "team-*" } else { "member-*" }

    # Get all team directories
    $teams = Get-ChildItem -Path $teamDir -Directory -Filter $teamPattern | Sort-Object Name

    foreach ($team in $teams) {
        $teamId = $team.Name -replace '^(team|member)-', ''
        $statusFile = Join-Path -Path $team.FullName -ChildPath "status.json"

        if (Test-Path $statusFile) {
            try {
                $status = Get-JsonContent -FilePath $statusFile

                if ($status) {
                    $teamStatus = $status.status ?? "Unknown"
                    $tasksCompleted = $status.tasks_completed ?? 0
                    $tasksFailed = $status.tasks_failed ?? 0

                    # Handle different JSON structures
                    $currentTask = $null
                    if ($status.current_task -is [string]) {
                        $currentTask = $status.current_task
                    }
                    elseif ($status.current_task -is [PSCustomObject]) {
                        $currentTask = $status.current_task.task_name
                    }
                    else {
                        $currentTask = "none"
                    }

                    # Truncate current task if too long
                    if ($currentTask -and $currentTask.Length -gt 25) {
                        $currentTask = $currentTask.Substring(0, 22) + "..."
                    }

                    # Set color based on status
                    $statusColor = switch -Wildcard ($teamStatus) {
                        "ready*" { $Colors.Green }
                        "completed*" { $Colors.Green }
                        "initialized*" { $Colors.Green }
                        "busy*" { $Colors.Blue }
                        "running*" { $Colors.Blue }
                        "failed*" { $Colors.Red }
                        "error*" { $Colors.Red }
                        default { $Colors.White }
                    }

                    # Update statistics
                    switch -Wildcard ($teamStatus) {
                        "ready*" { $completedTeams++ }
                        "completed*" { $completedTeams++ }
                        "busy*" { $activeTeams++ }
                        "running*" { $activeTeams++ }
                        "failed*" { $failedTeams++ }
                        "error*" { $failedTeams++ }
                    }

                    $totalCompleted += $tasksCompleted
                    $totalFailed += $tasksFailed

                    # Display team status
                    Write-Host ("{0,-8}" -f "Team $teamId") -NoNewline
                    Write-Host (" {0,-15}" -f $teamStatus) -NoNewline -ForegroundColor $statusColor
                    Write-Host (" {0,-15} {1,-15} {2,-25}" -f $tasksCompleted, $tasksFailed, $currentTask)
                }
                else {
                    Write-Host ("{0,-8} {1,-15} {2,-15} {3,-15} {4,-25}" -f "Team $teamId", "Invalid", "-", "-", "-")
                }
            }
            catch {
                Write-Debug2 "Error reading status for team $teamId: $_"
                Write-Host ("{0,-8} {1,-15} {2,-15} {3,-15} {4,-25}" -f "Team $teamId", "Error", "-", "-", "-")
            }
        }
        else {
            Write-Host ("{0,-8} {1,-15} {2,-15} {3,-15} {4,-25}" -f "Team $teamId", "Not found", "-", "-", "-") -ForegroundColor $Colors.Yellow
        }
    }

    # Display summary
    Write-Host "`nSummary:" -ForegroundColor $Colors.Cyan
    Write-Host "  Active Teams: $activeTeams" -ForegroundColor $Colors.Blue
    Write-Host "  Completed Teams: $completedTeams" -ForegroundColor $Colors.Green
    Write-Host "  Failed Teams: $failedTeams" -ForegroundColor $Colors.Red
    Write-Host "  Total Tasks Completed: $totalCompleted"
    Write-Host "  Total Tasks Failed: $totalFailed"

    # Calculate success rate
    if (($totalCompleted + $totalFailed) -gt 0) {
        $successRate = [math]::Round(($totalCompleted / ($totalCompleted + $totalFailed)) * 100, 1)
        Write-Host "  Success Rate: $successRate%" -ForegroundColor $(if ($successRate -gt 80) { $Colors.Green } else { $Colors.Yellow })
    }
}

# Display complete status report
function Show-StatusReport {
    param (
        [string]$Format = "text"
    )

    switch ($Format) {
        "json" {
            # Generate JSON output
            Write-Warning2 "JSON output format not fully implemented yet"
            $statusData = @{
                timestamp         = Get-Date -Format "o"
                deployment_status = Get-JsonContent -FilePath $DeploymentStatusFile
            }
            $statusData | ConvertTo-Json -Depth 10
        }

        "csv" {
            # Generate CSV output
            Write-Warning2 "CSV output format not fully implemented yet"
            $teams = Get-ChildItem -Path (Join-Path -Path $BuildDir -ChildPath "teams") -Directory -Filter "team-*" | Sort-Object Name
            foreach ($team in $teams) {
                $teamId = $team.Name -replace '^team-', ''
                $statusFile = Join-Path -Path $team.FullName -ChildPath "status.json"
                if (Test-Path $statusFile) {
                    $status = Get-JsonContent -FilePath $statusFile
                    [PSCustomObject]@{
                        TeamID         = $teamId
                        Status         = $status.status
                        TasksCompleted = $status.tasks_completed
                        TasksFailed    = $status.tasks_failed
                        CurrentTask    = $status.current_task
                    } | ConvertTo-Csv -NoTypeInformation
                }
            }
        }

        default {
            # Default text format with colored output
            Clear-Host

            Measure-ExecutionTime -Name "deployment_status" -ScriptBlock { Show-DeploymentStatus }

            Write-Host ""

            Measure-ExecutionTime -Name "team_status" -ScriptBlock { Show-TeamStatus }

            Write-Host ""

            Measure-ExecutionTime -Name "system_resources" -ScriptBlock { Show-SystemResources }

            if ($BenchmarkEnabled) {
                Write-Host ""
                Show-PerformanceMetrics
            }

            Write-Host ""
            Write-Host "Press Ctrl+C to exit monitoring (refreshing every $RefreshInterval seconds)" -ForegroundColor $Colors.Cyan
        }
    }
}

#endregion

# Main execution logic
function Start-Monitoring {
    try {
        Write-Info "Starting Ninja Team Status Reporter v2.0.0 (PowerShell Edition)"
        Write-Debug2 "Team Size: $TeamSize"
        Write-Debug2 "Refresh Interval: $RefreshInterval seconds"
        Write-Debug2 "Build Directory: $BuildDir"

        # Confirm build directory exists
        if (!(Test-Path $BuildDir)) {
            Write-Warning2 "Build directory does not exist: $BuildDir"
            try {
                New-Item -Path $BuildDir -ItemType Directory -Force | Out-Null
                Write-Info "Created build directory: $BuildDir"
            }
            catch {
                Write-Fatal "Cannot create build directory: $BuildDir. Error: $_"
            }
        }

        # Main monitoring loop
        while ($true) {
            $Global:StartTime = Get-Date
            Show-StatusReport -Format $OutputFormat
            Start-Sleep -Seconds $RefreshInterval
        }
    }
    catch {
        if ($_.Exception.Message -ne "Monitoring stopped by user") {
            Write-Error2 "Monitoring failed: $_"
            throw
        }
    }
    finally {
        Write-Info "Ninja Team Status Reporter stopped"
    }
}

# Run the monitor
try {
    Start-Monitoring
}
catch {
    if ($_.Exception.Message -ne "Monitoring stopped by user") {
        Write-Host "Error: $_" -ForegroundColor $Colors.Red
        exit 1
    }
}
