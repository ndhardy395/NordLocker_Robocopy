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
        [string]$Destination
    )

    # Verify that the source directory exists.
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        Write-Host "ERROR: Source directory does not exist." -ForegroundColor Red
        return
    }

    # Create destination directory if necessary.
    if (-not (Test-Path -LiteralPath $Destination)) {
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

    Write-Host "`nStarting development backup..." -ForegroundColor Cyan

    Write-Host "Source:      $Source"
    Write-Host "Destination: $Destination`n"

    # Execute Robocopy.
    robocopy $Source $Destination /E `
        /XD $ExcludedDirectories `
        /XF $ExcludedFiles `
        /R:2 `
        /W:2

    # Robocopy uses exit codes 0-7 for successful outcomes.
    if ($LASTEXITCODE -lt 8) {
        Write-Host "`nBackup completed successfully!" -ForegroundColor Green
    }
    else {
        Write-Host "`nBackup encountered an error. Exit code: $LASTEXITCODE" -ForegroundColor Red
    }
}
