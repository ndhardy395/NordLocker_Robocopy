<#
.SYNOPSIS
    Backs up development projects while excluding unnecessary files.

.DESCRIPTION
    Uses Robocopy to copy development projects into a backup directory.
    Preserves Git repositories while excluding generated build artifacts.

.NOTES
    Author: Mr. Hardy
#>

function Backup-DevelopmentProject {

    param(
        # Original development project location.
        [Parameter(Mandatory = $true)]
        [string]$Source,

        # Destination backup location.
        [Parameter(Mandatory = $true)]
        [string]$Destination,

        # Preview what would be copied without copying or creating anything.
        [switch]$DryRun
    )

    # Verify that the source directory exists.
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        Write-Host "ERROR: Source directory does not exist." -ForegroundColor Red
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

    Write-Host "Source:      $Source"
    Write-Host "Destination: $Destination`n"

    # Execute Robocopy.
    robocopy $Source $Destination /E `
        /XD $ExcludedDirectories `
        /XF $ExcludedFiles `
        /R:2 `
        /W:2 `
        $DryRunOptions

    # Robocopy uses exit codes 0-7 for successful outcomes.
    # During a dry run the exit code describes what WOULD have happened.
    if ($LASTEXITCODE -lt 8) {
        if ($DryRun) {
            Write-Host "`nDry run completed. No files were copied." -ForegroundColor Yellow
        }
        else {
            Write-Host "`nBackup completed successfully!" -ForegroundColor Green
        }
    }
    else {
        Write-Host "`nBackup encountered an error. Exit code: $LASTEXITCODE" -ForegroundColor Red
    }
}
