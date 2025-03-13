<#
.SYNOPSIS
    Real-time monitoring script for ninja team tasks (Windows PowerShell version)
.DESCRIPTION
    Monitors the execution of ninja team tasks across multiple team members
.PARAMETER TaskName
    Name of the task to monitor
.PARAMETER TeamSize
    Number of team members to monitor (default: determined from config or environment)
.PARAMETER RefreshInterval
    Seconds between UI refreshes (default: 2 seconds)
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$TaskName,

    [Parameter(Mandatory = $false)]
    [int]$TeamSize = 0,

    [Parameter(Mandatory = $false)]
    [int]$RefreshInterval = 2
)

# Configure error handling
$ErrorActionPreference = "Stop"

# Import environment from config if possible
function Import-NinjaConfig {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $projectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $scriptDir))
    $configFile = Join-Path -Path $projectRoot -ChildPath "scripts\ninja\config\deploy-config.json"

    if (Test-Path $configFile) {
        try {
            $config = Get-Content -Path $configFile -Raw | ConvertFrom-Json
            return @{
                TeamSize = $config.deployment.team.size
                BuildDir = Join-Path -Path $projectRoot -ChildPath "build\ninja"
            }
        }
        catch {
            Write-Warning "Failed to parse config file: $_"
        }
    }

    # Default values
    return @{
        TeamSize = 12
        BuildDir = Join-Path -Path $projectRoot -ChildPath "build\ninja"
    }
}

# Get configuration
$config = Import-NinjaConfig
if ($TeamSize -le 0) {
    $TeamSize = $config.TeamSize
}
$buildDir = $config.BuildDir

# Colors for output
$colors = @{
    Success   = "Green"
    Warning   = "Yellow"
    Error     = "Red"
    Info      = "Cyan"
    Highlight = "White"
    Default   = "Gray"
}

# Function to display a progress bar
function Show-TeamProgressBar {
    param (
        [int]$Completed,
        [int]$Total,
        [int]$Width = 40
    )

    $percent = if ($Total -gt 0) { [Math]::Floor(($Completed / $Total) * 100) } else { 0 }
    $filledWidth = [Math]::Floor(($Width * $percent) / 100)
    $emptyWidth = $Width - $filledWidth

    $progressBar = "[" + ("█" * $filledWidth) + ("-" * $emptyWidth) + "]"
    Write-Host -NoNewline $progressBar
    Write-Host -NoNewline " $percent% ($Completed/$Total)"
}

# Function to format timestamp
function Format-Timestamp {
    return Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}

# Function to get team member status
function Get-TeamMemberStatus {
    param (
        [int]$MemberId
    )

    $memberDir = Join-Path -Path $buildDir -ChildPath "team\member-$MemberId"
    $statusFile = Join-Path -Path $memberDir -ChildPath "status.json"

    if (-not (Test-Path $statusFile)) {
        return @{
            MemberId       = $MemberId
            Status         = "unknown"
            TasksCompleted = 0
            TasksFailed    = 0
            CurrentTask    = $null
            LastUpdated    = $null
        }
    }

    try {
        $statusJson = Get-Content $statusFile -Raw | ConvertFrom-Json

        return @{
            MemberId       = $MemberId
            Status         = $statusJson.status
            TasksCompleted = [int]($statusJson.tasks_completed ?? 0)
            TasksFailed    = [int]($statusJson.tasks_failed ?? 0)
            CurrentTask    = $statusJson.current_task
            LastUpdated    = $statusJson.last_updated
        }
    }
    catch {
        Write-Warning "Failed to parse status for member $MemberId`: $_"
        return @{
            MemberId       = $MemberId
            Status         = "error"
            TasksCompleted = 0
            TasksFailed    = 0
            CurrentTask    = $null
            LastUpdated    = $null
            Error          = $_.Exception.Message
        }
    }
}

# Function to get task execution progress for a specific member
function Get-TaskProgress {
    param (
        [int]$MemberId,
        [string]$TaskName
    )

    $memberDir = Join-Path -Path $buildDir -ChildPath "team\member-$MemberId"
    $workspaceDir = Join-Path -Path $memberDir -ChildPath "workspace\$TaskName"
    $logFile = Join-Path -Path $memberDir -ChildPath "logs\$TaskName.log"

    # Default values
    $result = @{
        Progress          = 0
        SubtasksTotal     = 0
        SubtasksCompleted = 0
        StartTime         = $null
        RunningTime       = $null
        LogEntries        = @()
        HasErrors         = $false
        LatestMessage     = "No information available"
    }

    # Check if the log file exists
    if (Test-Path $logFile) {
        try {
            # Get log file content
            $logContent = Get-Content $logFile -ErrorAction SilentlyContinue

            # Get the latest few log entries
            $result.LogEntries = $logContent | Select-Object -Last 5

            # Get the latest message
            if ($logContent.Count -gt 0) {
                $result.LatestMessage = $logContent | Select-Object -Last 1
            }

            # Check for start timestamp
            $startTimeEntry = $logContent | Select-String -Pattern "\[INFO\] Starting task execution" | Select-Object -First 1
            if ($startTimeEntry) {
                $timestampMatch = [regex]::Match($startTimeEntry, '\[([\d\-]+\s[\d:]+)\]')
                if ($timestampMatch.Success) {
                    try {
                        $result.StartTime = [DateTime]::ParseExact($timestampMatch.Groups[1].Value, "yyyy-MM-dd HH:mm:ss", $null)
                        $result.RunningTime = (Get-Date) - $result.StartTime
                    }
                    catch {
                        # Ignore parsing errors
                    }
                }
            }

            # Check for subtask information
            $subtasksMatch = $logContent | Select-String -Pattern "Executing subtask (\d+)/(\d+)" | Select-Object -Last 1
            if ($subtasksMatch -and $subtasksMatch.Matches.Count -gt 0) {
                $result.SubtasksCompleted = [int]$subtasksMatch.Matches[0].Groups[1].Value
                $result.SubtasksTotal = [int]$subtasksMatch.Matches[0].Groups[2].Value

                # Calculate progress percentage
                if ($result.SubtasksTotal -gt 0) {
                    $result.Progress = [Math]::Floor(($result.SubtasksCompleted / $result.SubtasksTotal) * 100)
                }
            }

            # Check for errors
            $result.HasErrors = ($logContent | Select-String -Pattern "ERROR" -SimpleMatch).Count -gt 0
        }
        catch {
            Write-Warning "Failed to analyze log for member $MemberId`: $_"
        }
    }

    # Check for completion marker
    $doneFile = Join-Path -Path $memberDir -ChildPath "$TaskName.done"
    if (Test-Path $doneFile) {
        $result.Progress = 100
        $result.SubtasksCompleted = $result.SubtasksTotal
        if ($result.SubtasksTotal -eq 0) {
            $result.SubtasksTotal = 1
            $result.SubtasksCompleted = 1
        }
        $result.LatestMessage = "Task completed successfully"
    }

    return $result
}

# Function to display task monitoring dashboard
function Show-MonitoringDashboard {
    param (
        [string]$TaskName
    )

    Clear-Host

    # Display header
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor $colors.Info
    Write-Host "║ PhotoPrism Ninja Team - Task Monitor                           ║" -ForegroundColor $colors.Info
    Write-Host "║ Task: $($TaskName.PadRight(56).Substring(0, 56)) ║" -ForegroundColor $colors.Info
    Write-Host "║ Time: $(Format-Timestamp.PadRight(56).Substring(0, 56)) ║" -ForegroundColor $colors.Info
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor $colors.Info
    Write-Host ""

    # Get deployment status
    $deploymentStatusFile = Join-Path -Path $buildDir -ChildPath "deployment-status.json"
    if (Test-Path $deploymentStatusFile) {
        try {
            $deploymentStatus = Get-Content $deploymentStatusFile -Raw | ConvertFrom-Json
            $statusColor = $colors.Info
            if ($deploymentStatus.status -eq "completed" -or $deploymentStatus.status -eq "deployed") {
                $statusColor = $colors.Success
            }
            elseif ($deploymentStatus.status -eq "failed") {
                $statusColor = $colors.Error
            }

            Write-Host "Deployment Status: " -NoNewline
            Write-Host $deploymentStatus.status -ForegroundColor $statusColor
            Write-Host "Environment: $($deploymentStatus.environment)"
            Write-Host "Last Updated: $($deploymentStatus.last_updated)"
            Write-Host ""
        }
        catch {
            Write-Warning "Failed to parse deployment status: $_"
        }
    }

    # Display team member statuses
    Write-Host "Team Member Status:" -ForegroundColor $colors.Highlight
    Write-Host "==============================================================="
    Write-Host "ID  | Status      | Progress | Tasks Comp/Fail | Current Task"
    Write-Host "---------------------------------------------------------------"

    $totalCompleted = 0
    $totalFailed = 0
    $activeMembers = 0
    $taskMembers = 0
    $membersWithErrors = 0

    for ($i = 1; $i -le $TeamSize; $i++) {
        $memberStatus = Get-TeamMemberStatus -MemberId $i
        $taskProgress = Get-TaskProgress -MemberId $i -TaskName $TaskName

        # Status color
        $statusColor = $colors.Default
        switch ($memberStatus.Status) {
            "ready" { $statusColor = $colors.Success }
            "busy" { $statusColor = $colors.Info }
            "initialized" { $statusColor = $colors.Info }
            "error" { $statusColor = $colors.Error }
            "failed" { $statusColor = $colors.Error }
        }

        # Track statistics
        $totalCompleted += $memberStatus.TasksCompleted
        $totalFailed += $memberStatus.TasksFailed
        if ($memberStatus.Status -eq "busy") { $activeMembers++ }
        if ($memberStatus.CurrentTask -eq $TaskName) { $taskMembers++ }
        if ($taskProgress.HasErrors) { $membersWithErrors++ }

        # Display member row
        $id = "$i".PadLeft(3)
        $status = "$($memberStatus.Status)".PadRight(11)

        Write-Host "$id | " -NoNewline
        Write-Host "$status" -ForegroundColor $statusColor -NoNewline
        Write-Host " | " -NoNewline

        # Display progress bar
        Write-Host "[" -NoNewline
        $progressChars = [Math]::Floor($taskProgress.Progress / 10)
        Write-Host ("■" * $progressChars) -NoNewline -ForegroundColor $colors.Success
        Write-Host (" " * (10 - $progressChars)) -NoNewline
        Write-Host "]" -NoNewline

        Write-Host " | " -NoNewline
        Write-Host "$($memberStatus.TasksCompleted)".PadLeft(2) -NoNewline
        Write-Host "/" -NoNewline
        Write-Host "$($memberStatus.TasksFailed)".PadLeft(2) -NoNewline
        Write-Host "         | " -NoNewline

        # Show current task (truncated)
        $currentTask = if ($memberStatus.CurrentTask) { $memberStatus.CurrentTask.Substring(0, [Math]::Min(20, $memberStatus.CurrentTask.Length)) } else { "-" }
        Write-Host $currentTask
    }

    Write-Host "---------------------------------------------------------------"

    # Display summary statistics
    Write-Host ""
    Write-Host "Summary:" -ForegroundColor $colors.Highlight
    Write-Host "  Active Members: $activeMembers / $TeamSize"
    Write-Host "  Members Working on Task: $taskMembers"
    Write-Host "  Total Tasks Completed: $totalCompleted"
    Write-Host "  Total Tasks Failed: $totalFailed"
    Write-Host "  Members with Errors: $membersWithErrors"
    Write-Host ""
    Write-Host "Overall Task Progress:" -ForegroundColor $colors.Highlight
    Write-Host "  " -NoNewline

    # Calculate overall progress based on team member progress
    $overallProgress = 0
    $progressMembers = 0
    for ($i = 1; $i -le $TeamSize; $i++) {
        $taskProgress = Get-TaskProgress -MemberId $i -TaskName $TaskName
        if ($taskProgress.Progress -gt 0) {
            $overallProgress += $taskProgress.Progress
            $progressMembers++
        }
    }

    if ($progressMembers -gt 0) {
        $overallProgress = [Math]::Floor($overallProgress / $progressMembers)
    }

    Show-TeamProgressBar -Completed $overallProgress -Total 100 -Width 50
    Write-Host ""

    # Display monitoring info
    Write-Host ""
    Write-Host "Press Ctrl+C to exit monitoring" -ForegroundColor $colors.Warning
}

# Main monitoring loop
try {
    while ($true) {
        Show-MonitoringDashboard -TaskName $TaskName
        Start-Sleep -Seconds $RefreshInterval
    }
}
catch {
    Write-Host "Monitoring ended: $_" -ForegroundColor $colors.Error
    exit 1
}
finally {
    Write-Host "Monitoring ended." -ForegroundColor $colors.Info
}
