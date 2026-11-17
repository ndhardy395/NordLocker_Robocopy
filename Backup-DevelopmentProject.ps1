# Backup-DevelopmentProject.ps1
# Dot-source this file to load the Backup-DevelopmentProject function:
#     . .\Backup-DevelopmentProject.ps1

function Write-BackupLog {
    <#
    .SYNOPSIS
        Shows a message in the console and appends it to the log file.
    #>
    param(
        # Text to record.
        [string]$Message,

        # Log file to append to. If empty, nothing is written to disk.
        [string]$LogFile,

        # Optional console color, for example "Red" or "Green".
        [string]$Color,

        # Write only to the log file, not to the console.
        [switch]$LogOnly
    )

    if (-not $LogOnly) {
        if ($Color) {
            Write-Host $Message -ForegroundColor $Color
        }
        else {
            Write-Host $Message
        }
    }

    if ($LogFile) {
        # Leading/trailing blank lines are for console spacing only,
        # so they are trimmed before the timestamp is added.
        $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -LiteralPath $LogFile -Value "[$Time] $($Message.Trim())"
    }
}

function Backup-DevelopmentProject {
    <#
    .SYNOPSIS
        Backs up development projects while excluding unnecessary files.

    .DESCRIPTION
        Uses Robocopy to copy development projects into a backup directory.
        Preserves Git repositories while excluding generated build artifacts.
        Every run (including dry runs) writes its own log file.

    .NOTES
        Author: Mr. Hardy
    #>

    # The help block above sits INSIDE the function so it always belongs to
    # this function, no matter what other code is placed above it in the file.

    param(
        # Original development project location.
        [Parameter(Mandatory = $true)]
        [string]$Source,

        # Destination backup location.
        [Parameter(Mandatory = $true)]
        [string]$Destination,

        # Preview what would be copied without copying or creating anything.
        [switch]$DryRun,

        # Folder where a log file is written for every run.
        # Defaults to a "Logs" folder next to this script.
        [string]$LogDirectory = (Join-Path $PSScriptRoot "Logs")
    )

    # ------------------------------------------------------------------
    # Logging setup
    # ------------------------------------------------------------------

    # Each run gets its own log file, named after the project folder and
    # the start time, for example: CalculatorApp_2026-11-17_15-50-23.log
    $ProjectName = Split-Path -Path $Source.TrimEnd('\', '/') -Leaf
    $LogName = "{0}_{1}" -f $ProjectName, (Get-Date -Format "yyyy-MM-dd_HH-mm-ss")
    if ($DryRun) {
        $LogName += "_DRYRUN"
    }
    $LogFile = Join-Path $LogDirectory "$LogName.log"

    # A logging problem (bad folder, no permission) should not stop the
    # backup itself, so failures here only produce a warning.
    # -ErrorAction Stop turns errors into exceptions that "catch" can handle.
    try {
        if (-not (Test-Path -LiteralPath $LogDirectory)) {
            New-Item -ItemType Directory -Path $LogDirectory -Force -ErrorAction Stop | Out-Null
        }

        # Create the log file now so any problem shows up before copying starts.
        # If two runs start in the same second they share one file: the second
        # run appends to it. No -Force here, so a log is never overwritten.
        if (-not (Test-Path -LiteralPath $LogFile)) {
            New-Item -ItemType File -Path $LogFile -ErrorAction Stop | Out-Null
        }
    }
    catch {
        Write-Warning "Could not create log file '$LogFile'. Continuing without logging. Reason: $($_.Exception.Message)"
        $LogFile = $null
    }

    if ($DryRun) { $Mode = "DRY RUN" } else { $Mode = "BACKUP" }
    Write-BackupLog -LogFile $LogFile -LogOnly -Message "Development backup started"
    Write-BackupLog -LogFile $LogFile -LogOnly -Message "Mode:        $Mode"
    Write-BackupLog -LogFile $LogFile -LogOnly -Message "Source:      $Source"
    Write-BackupLog -LogFile $LogFile -LogOnly -Message "Destination: $Destination"

    # ------------------------------------------------------------------
    # Backup
    # ------------------------------------------------------------------

    # Verify that the source directory exists.
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        Write-BackupLog -LogFile $LogFile -Color Red -Message "ERROR: Source directory does not exist."
        return
    }

    # Create destination directory if necessary.
    # Skipped during a dry run so that a preview never changes the disk.
    if (-not $DryRun -and -not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    # Directories that should not be included.
    $ExcludedDirectories = @(
        ".vs",
        "x64",
        "Debug",
        "Release",
        "bin",
        "obj"
    )

    # Files that should not be included.
    $ExcludedFiles = @(
        "*.user",
        "*.suo",
        "*.cache"
    )

    # Extra Robocopy switches that only apply to some runs.
    # /L means "list only": Robocopy reports every file it WOULD copy,
    # but copies, overwrites, and creates nothing.
    # An empty array adds no arguments, so a normal run is unchanged.
    $DryRunOptions = @()
    if ($DryRun) {
        $DryRunOptions = @("/L")
        Write-Host "`nStarting development backup (DRY RUN - nothing will be copied)..." -ForegroundColor Yellow
    }
    else {
        Write-Host "`nStarting development backup..." -ForegroundColor Cyan
    }

    # /LOG+:<file> appends Robocopy's full report to our log file.
    # /TEE keeps showing that report in the console as well.
    $LogOptions = @()
    if ($LogFile) {
        $LogOptions = @("/LOG+:$LogFile", "/TEE")
    }

    Write-Host "Source:      $Source"
    Write-Host "Destination: $Destination`n"

    # Execute Robocopy.
    robocopy $Source $Destination /E `
        /XD $ExcludedDirectories `
        /XF $ExcludedFiles `
        /R:2 `
        /W:2 `
        $DryRunOptions `
        $LogOptions

    # Save the exit code right away; running other programs would replace it.
    $ExitCode = $LASTEXITCODE
    Write-BackupLog -LogFile $LogFile -LogOnly -Message "Robocopy exit code: $ExitCode"

    # Robocopy uses exit codes 0-7 for successful outcomes.
    # During a dry run the exit code describes what WOULD have happened.
    if ($ExitCode -lt 8) {
        if ($DryRun) {
            Write-BackupLog -LogFile $LogFile -Color Yellow -Message "`nDry run completed. No files were copied."
        }
        else {
            Write-BackupLog -LogFile $LogFile -Color Green -Message "`nBackup completed successfully!"
        }
    }
    else {
        Write-BackupLog -LogFile $LogFile -Color Red -Message "`nBackup encountered an error. Exit code: $ExitCode"
    }

    if ($LogFile) {
        Write-Host "Log file:    $LogFile"
    }
}
