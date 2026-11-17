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

function Get-RobocopySummary {
    <#
    .SYNOPSIS
        Reads the totals table at the end of Robocopy's output.
    .DESCRIPTION
        Robocopy (run with /BYTES) finishes with a table like this:

                       Total    Copied   Skipped  Mismatch    FAILED    Extras
            Dirs :        41         0        41         0         0         0
           Files :        55         1        54         0         0         1
           Bytes :     30910        68     30842         0         0        16

        Returns a hashtable with a "Dirs", "Files", and "Bytes" entry, each
        holding the six numbers. Returns $null if no table was found (for
        example, Robocopy stopped with a fatal error before finishing).
    #>
    param(
        # Every line Robocopy printed.
        [string[]]$Output
    )

    $Summary = @{}

    foreach ($Line in $Output) {
        # A regular expression: a row name, a colon, then exactly six numbers.
        # Each ( ) group is "captured" and can be read from $Matches afterwards.
        if ($Line -match '^\s*(Dirs|Files|Bytes)\s*:\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*$') {
            $Summary[$Matches[1]] = [PSCustomObject]@{
                Total    = [long]$Matches[2]
                Copied   = [long]$Matches[3]
                Skipped  = [long]$Matches[4]
                Mismatch = [long]$Matches[5]
                Failed   = [long]$Matches[6]
                Extras   = [long]$Matches[7]
            }
        }
    }

    # Only trust the table if all three rows were found.
    if ($Summary.Count -eq 3) {
        return $Summary
    }
    return $null
}

function Format-ByteSize {
    <#
    .SYNOPSIS
        Turns a byte count into readable text, such as "30.2 KB" or "1.45 GB".
    #>
    param(
        [long]$Bytes
    )

    # 1KB, 1MB, and 1GB are built-in PowerShell numbers (1024, 1048576, ...).
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N1} KB" -f ($Bytes / 1KB) }
    return "$Bytes bytes"
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
        A PSCustomObject with Success, ExitCode, DryRun, a summary (FilesCopied,
        BytesCopied, FilesSkipped, FilesFailed, FilesExtra), the backup's size
        (BackupFiles, BackupBytes), Duration, Source, Destination, LogFile,
        and Message, so calling scripts can check what happened.

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
    # The summary numbers stay $null if Robocopy never ran or gave no totals.
    $StartTime = Get-Date
    $Result = [PSCustomObject]@{
        Success      = $false
        ExitCode     = $null     # Robocopy's exit code; stays $null if Robocopy never ran.
        DryRun       = [bool]$DryRun
        FilesCopied  = $null     # Copied (or, in a dry run, would be copied).
        BytesCopied  = $null     # Size of those files.
        FilesSkipped = $null     # Not copied: unchanged, or excluded by a file pattern.
        FilesFailed  = $null     # Could not be copied.
        FilesExtra   = $null     # Exist only in the backup (left alone).
        BackupFiles  = $null     # Files in the backup folder afterwards (not set for dry runs).
        BackupBytes  = $null     # Storage the backup folder uses afterwards (not set for dry runs).
        Duration     = $null     # How long the run took.
        Source       = $Source
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
        $Result.Duration = (Get-Date) - $StartTime
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
            $Result.Duration = (Get-Date) - $StartTime
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
    # /BYTES makes Robocopy print exact byte counts ("30910") instead of
    # rounded sizes ("30.2 k"), so the totals can be read reliably.
    #
    # "Tee-Object -Variable" keeps a copy of every line in $RobocopyOutput
    # (for the summary below) while passing each line along unchanged.
    # "| Out-Host" then sends the lines straight to the console. Without it,
    # every line Robocopy prints would become part of this function's OUTPUT,
    # and a caller would receive dozens of text lines mixed in with $Result.
    robocopy $Source $Destination /E `
        /XD $ExcludedDirectories `
        /XF $ExcludedFiles `
        /R:2 `
        /W:2 `
        /BYTES `
        $DryRunOptions `
        $LogOptions | Tee-Object -Variable RobocopyOutput | Out-Host

    # Save the exit code right away; running other programs would replace it.
    $ExitCode = $LASTEXITCODE
    $Result.ExitCode = $ExitCode
    Write-BackupLog -LogFile $LogFile -LogOnly -Message "Robocopy exit code: $ExitCode"

    # ------------------------------------------------------------------
    # Summary
    # ------------------------------------------------------------------

    # Note: Robocopy counts files excluded by a FILE pattern (*.user, ...)
    # as "Skipped", but does not count anything inside an excluded FOLDER.
    # That is why "Skipped" means "unchanged, or excluded by a file pattern".
    $Summary = Get-RobocopySummary -Output $RobocopyOutput
    if ($Summary) {
        $Result.FilesCopied  = $Summary.Files.Copied
        $Result.BytesCopied  = $Summary.Bytes.Copied
        $Result.FilesSkipped = $Summary.Files.Skipped
        $Result.FilesFailed  = $Summary.Files.Failed
        $Result.FilesExtra   = $Summary.Files.Extras

        if ($DryRun) { $Verb = "would be copied" } else { $Verb = "copied" }
        $SummaryText = "Summary: {0} file(s) {1} ({2}), {3} skipped (unchanged or excluded by a file pattern), {4} failed, {5} only in backup." -f `
            $Result.FilesCopied, $Verb, (Format-ByteSize $Result.BytesCopied),
            $Result.FilesSkipped, $Result.FilesFailed, $Result.FilesExtra
        Write-BackupLog -LogFile $LogFile -Message "`n$SummaryText"
    }
    else {
        # Happens when Robocopy stops before printing its totals (a fatal
        # error), or if Windows shows Robocopy's report in another language.
        Write-BackupLog -LogFile $LogFile -Message "`nSummary: not available (Robocopy did not report totals)."
    }

    # Storage usage: measure the backup folder itself after a real run.
    # -Force is needed to include HIDDEN items; without it the .git folder
    # (hidden on Windows) would be left out of the count.
    # Skipped for dry runs, because nothing was copied.
    if (-not $DryRun -and (Test-Path -LiteralPath $Destination -PathType Container)) {
        try {
            $BackupContents = Get-ChildItem -LiteralPath $Destination -Recurse -File -Force -ErrorAction Stop |
                Measure-Object -Property Length -Sum
            $Result.BackupFiles = $BackupContents.Count
            $Result.BackupBytes = [long]$BackupContents.Sum
            Write-BackupLog -LogFile $LogFile -Message ("Backup size: {0} file(s), {1}." -f $Result.BackupFiles, (Format-ByteSize $Result.BackupBytes))
        }
        catch {
            Write-BackupLog -LogFile $LogFile -Message "Backup size: could not be measured. $($_.Exception.Message)"
        }
    }

    $Result.Duration = (Get-Date) - $StartTime
    Write-BackupLog -LogFile $LogFile -Message ("Duration:    {0:N1} seconds." -f $Result.Duration.TotalSeconds)

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
