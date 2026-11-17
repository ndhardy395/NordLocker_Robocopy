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

    .OUTPUTS
        A PSCustomObject with Success, ExitCode, DryRun, Source, Destination,
        LogFile, and Message, so calling scripts can check whether it worked.

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
    # Result object
    # ------------------------------------------------------------------

    # This object is what the function hands back to whoever called it, so
    # another script can check $Result.Success instead of reading the console.
    # It starts out as a failure and is updated as the run progresses.
    $Result = [PSCustomObject]@{
        Success     = $false
        ExitCode    = $null      # Robocopy's exit code; stays $null if Robocopy never ran.
        DryRun      = [bool]$DryRun
        Source      = $Source
        Destination = $Destination
        LogFile     = $null
        Message     = ""
    }

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
    $Result.LogFile = $LogFile

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
        $Result.Message = "Source directory does not exist."
        Write-BackupLog -LogFile $LogFile -Color Red -Message "ERROR: $($Result.Message)"
        return $Result
    }

    # Create destination directory if necessary.
    # Skipped during a dry run so that a preview never changes the disk.
    # If the folder can't be created (bad drive letter, no permission),
    # stop here with a clear message instead of letting Robocopy fail.
    if (-not $DryRun -and -not (Test-Path -LiteralPath $Destination)) {
        try {
            New-Item -ItemType Directory -Path $Destination -Force -ErrorAction Stop | Out-Null

            # New-Item -Force can silently do nothing (for example when part of
            # the path is a file), so confirm the folder really exists.
            # "throw" raises our own error, which jumps to the catch block below.
            if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
                throw "The folder was not created. Check that no part of the path is a file."
            }
        }
        catch {
            $Result.Message = "Could not create destination directory. $($_.Exception.Message)"
            Write-BackupLog -LogFile $LogFile -Color Red -Message "ERROR: $($Result.Message)"
            return $Result
        }
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
    # "| Out-Host" sends Robocopy's text straight to the console. Without it,
    # every line Robocopy prints would become part of this function's OUTPUT,
    # and a caller would receive dozens of text lines mixed in with $Result.
    robocopy $Source $Destination /E `
        /XD $ExcludedDirectories `
        /XF $ExcludedFiles `
        /R:2 `
        /W:2 `
        $DryRunOptions `
        $LogOptions | Out-Host

    # Save the exit code right away; running other programs would replace it.
    $ExitCode = $LASTEXITCODE
    $Result.ExitCode = $ExitCode
    Write-BackupLog -LogFile $LogFile -LogOnly -Message "Robocopy exit code: $ExitCode"

    # Robocopy uses exit codes 0-7 for successful outcomes.
    # During a dry run the exit code describes what WOULD have happened.
    if ($ExitCode -lt 8) {
        $Result.Success = $true
        if ($DryRun) {
            $Result.Message = "Dry run completed. No files were copied."
            Write-BackupLog -LogFile $LogFile -Color Yellow -Message "`n$($Result.Message)"
        }
        else {
            $Result.Message = "Backup completed successfully!"
            Write-BackupLog -LogFile $LogFile -Color Green -Message "`n$($Result.Message)"
        }
    }
    else {
        $Result.Message = "Backup encountered an error. Exit code: $ExitCode"
        Write-BackupLog -LogFile $LogFile -Color Red -Message "`n$($Result.Message)"
    }

    if ($LogFile) {
        Write-Host "Log file:    $LogFile"
    }

    return $Result
}
