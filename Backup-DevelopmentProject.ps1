# Backup-DevelopmentProject.ps1
# Dot-source this file to load its functions:
#     . .\Backup-DevelopmentProject.ps1
#
# Main commands:
#     Backup-DevelopmentProject   Back up one project folder.
#     Find-GitRepository          List the Git repositories under a folder.
#     Backup-GitRepository        Find every Git repository under a folder and back each one up.
#     Get-ExclusionProfile        List the exclusion profiles (VisualStudio, Unity, Unreal, ...).

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

function Get-ExclusionProfile {
    <#
    .SYNOPSIS
        Lists the exclusion profiles, or returns the exclusions for one or more of them.

    .DESCRIPTION
        An exclusion profile is a named set of generated folders and files to
        leave out of a backup, for one kind of development environment.

        Each profile has three lists:
          Directories      Folder names excluded at ANY depth (wildcards allowed).
          RootDirectories  Folder names excluded only at the TOP of the project
                           (no wildcards). Used for names like "Library" or
                           "Logs" that could also be real folders deeper inside.
          Files            File name patterns excluded anywhere.

        Several profiles can be combined; their lists are merged.
        To add or change a profile, edit $AllProfiles below.

    .EXAMPLE
        Get-ExclusionProfile
        Lists every available profile.

    .EXAMPLE
        Get-ExclusionProfile -Name Unity, VisualStudio
        Returns the merged exclusions of both profiles.
    #>
    param(
        # Profile name(s). Leave out to list all profiles.
        [string[]]$Name
    )

    # [ordered] keeps the profiles in the order they are written here.
    $AllProfiles = [ordered]@{
        VisualStudio = @{
            Description     = "Visual Studio C++/C# build output (the original default)."
            Directories     = @(".vs", "x64", "Debug", "Release", "bin", "obj")
            RootDirectories = @()
            Files           = @("*.user", "*.suo", "*.cache")
        }
        Unity = @{
            Description     = "Unity projects: caches and builds Unity regenerates."
            Directories     = @(".vs")
            RootDirectories = @("Library", "Temp", "Obj", "Build", "Builds", "Logs",
                                "UserSettings", "MemoryCaptures", "Recordings")
            Files           = @("*.csproj", "*.sln", "*.suo", "*.user", "*.pidb",
                                "*.booproj", "*.svd", "*.pdb", "*.mdb", "*.opendb", "*.VC.db")
        }
        Unreal = @{
            Description     = "Unreal Engine projects: compiled binaries and caches."
            Directories     = @(".vs", "Binaries", "Intermediate", "DerivedDataCache")
            RootDirectories = @("Saved")
            Files           = @("*.sln", "*.suo", "*.user", "*.VC.db", "*.opensdf", "*.sdf")
        }
        CMake = @{
            Description     = "CMake projects: build folders (including CLion's and Visual Studio's)."
            Directories     = @(".vs", "cmake-build-*")
            RootDirectories = @("build", "out")
            Files           = @()
        }
        Godot = @{
            Description     = "Godot projects: the import cache Godot rebuilds."
            Directories     = @()
            RootDirectories = @(".godot", ".import")
            Files           = @()
        }
    }

    # No name given: show what's available.
    if (-not $Name) {
        foreach ($Key in $AllProfiles.Keys) {
            [PSCustomObject]@{
                Name            = $Key
                Description     = $AllProfiles[$Key].Description
                Directories     = $AllProfiles[$Key].Directories -join ", "
                RootDirectories = $AllProfiles[$Key].RootDirectories -join ", "
                Files           = $AllProfiles[$Key].Files -join ", "
            }
        }
        return
    }

    $Directories     = @()
    $RootDirectories = @()
    $Files           = @()

    foreach ($ProfileName in $Name) {
        # .Contains on an [ordered] table ignores upper/lower case,
        # so "unity" and "Unity" both work.
        if (-not $AllProfiles.Contains($ProfileName)) {
            throw "Unknown exclusion profile '$ProfileName'. Available profiles: $($AllProfiles.Keys -join ', ')."
        }
        $Directories     += $AllProfiles[$ProfileName].Directories
        $RootDirectories += $AllProfiles[$ProfileName].RootDirectories
        $Files           += $AllProfiles[$ProfileName].Files
    }

    # Top-level folders are passed to Robocopy as full paths, and Robocopy
    # stops with a fatal error if a full path contains a wildcard.
    $WildcardRoots = @($RootDirectories | Where-Object { $_ -match '[*?]' })
    if ($WildcardRoots.Count -gt 0) {
        throw "RootDirectories cannot contain wildcards (* or ?): $($WildcardRoots -join ', '). Move them to Directories instead."
    }

    return [PSCustomObject]@{
        Name            = $Name -join ", "
        Directories     = @($Directories | Select-Object -Unique)
        RootDirectories = @($RootDirectories | Select-Object -Unique)
        Files           = @($Files | Select-Object -Unique)
    }
}

function Get-DefaultLogDirectory {
    <#
    .SYNOPSIS
        Returns the default log folder: %LOCALAPPDATA%\DevelopmentBackup\Logs
    .DESCRIPTION
        LOCALAPPDATA (usually C:\Users\<you>\AppData\Local) is where Windows
        programs keep their own files for the current user. Keeping logs
        there, rather than inside this project, means backing up this
        project never copies its own log files along with it.
    #>
    return (Join-Path $env:LOCALAPPDATA "DevelopmentBackup\Logs")
}

function Get-FullPath {
    <#
    .SYNOPSIS
        Turns a path such as ".\MyGame" into a full path like "C:\Projects\MyGame".
    .DESCRIPTION
        Uses PowerShell's current location (the folder shown in your prompt)
        and works even if the path does not exist yet.
    #>
    param(
        [string]$Path
    )

    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Test-IsSameOrInside {
    <#
    .SYNOPSIS
        Returns $true if -Path is the same folder as -Folder, or inside it.
    #>
    param(
        [string]$Path,
        [string]$Folder
    )

    # Ending both with "\" stops "C:\Projects2" from counting as inside
    # "C:\Projects". Windows paths ignore upper/lower case, so the
    # comparison does too.
    $PathWithSlash   = $Path.TrimEnd('\') + '\'
    $FolderWithSlash = $Folder.TrimEnd('\') + '\'
    return $PathWithSlash.StartsWith($FolderWithSlash, [System.StringComparison]::OrdinalIgnoreCase)
}

function Find-GitRepository {
    <#
    .SYNOPSIS
        Lists the Git repositories found under a folder.

    .DESCRIPTION
        A folder counts as a Git repository if it contains a ".git" entry.
        Once a repository is found, the search does not look inside it:
        backing up that repository already includes everything inside it.

        Shortcut-like folders (symbolic links and junctions) are skipped,
        because they can point back to a parent folder and loop forever.

    .EXAMPLE
        Find-GitRepository -Path "C:\Users\Me\source\repos"
    #>
    param(
        # Folder to search.
        [Parameter(Mandatory = $true)]
        [string]$Path,

        # How many folder levels below -Path to search.
        # 0 = only check -Path itself, 1 = its subfolders too, and so on.
        [int]$MaxDepth = 4
    )

    # Is this folder itself a repository? (".git" is usually a folder, but
    # can be a file for Git worktrees, so any kind of item counts.)
    if (Test-Path -LiteralPath (Join-Path $Path ".git")) {
        return (Get-FullPath $Path)
    }

    # Stop when we've gone deep enough.
    if ($MaxDepth -le 0) {
        return
    }

    # Otherwise, search each subfolder the same way. A function calling
    # itself like this is called RECURSION; MaxDepth goes down by one each
    # level, which guarantees it eventually stops.
    # -Force includes hidden folders; -ErrorAction SilentlyContinue skips
    # folders we don't have permission to open.
    $Subfolders = Get-ChildItem -LiteralPath $Path -Directory -Force -ErrorAction SilentlyContinue

    foreach ($Subfolder in $Subfolders) {
        $IsLink = $Subfolder.Attributes -band [System.IO.FileAttributes]::ReparsePoint
        if (-not $IsLink) {
            Find-GitRepository -Path $Subfolder.FullName -MaxDepth ($MaxDepth - 1)
        }
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
        A PSCustomObject with Success, ExitCode, DryRun, ExclusionProfile, a summary (FilesCopied,
        BytesCopied, FilesSkipped, FilesFailed, FilesExtra), the backup's size
        (BackupFiles, BackupBytes), BundleFile, Duration, Source, Destination,
        LogFile, and Message, so calling scripts can check what happened.

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

        # Which generated files to leave out. One or more profile names;
        # run Get-ExclusionProfile to list them. Default: VisualStudio.
        [string[]]$ExclusionProfile = @("VisualStudio"),

        # Folder where a log file is written for every run.
        # Defaults to %LOCALAPPDATA%\DevelopmentBackup\Logs.
        [string]$LogDirectory = (Get-DefaultLogDirectory)
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
        ExclusionProfile = $ExclusionProfile -join ", "
        FilesCopied  = $null     # Copied (or, in a dry run, would be copied).
        BytesCopied  = $null     # Size of those files.
        FilesSkipped = $null     # Not copied: unchanged, or excluded by a file pattern.
        FilesFailed  = $null     # Could not be copied.
        FilesExtra   = $null     # Exist only in the backup (left alone).
        BackupFiles  = $null     # Files in the backup folder afterwards (not set for dry runs).
        BackupBytes  = $null     # Storage the backup folder uses afterwards (not set for dry runs).
        BundleFile   = $null     # Git history bundle created this run (Git repositories only).
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
    Write-BackupLog -LogFile $LogFile -LogOnly -Message "Exclusions:  $($ExclusionProfile -join ', ')"

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

    # Refuse to back up a folder into itself or into one of its own
    # subfolders. Robocopy would then copy the backup into the backup.
    if (Test-IsSameOrInside -Path (Get-FullPath $Destination) -Folder (Get-FullPath $Source)) {
        $Result.Message = "Destination is the same as the source or inside it. Choose a destination outside the project."
        Write-BackupLog -LogFile $LogFile -Color Red -Message "ERROR: $($Result.Message)"
        $Result.Duration = (Get-Date) - $StartTime
        return $Result
    }

    # Look up the exclusion profile(s) before creating anything, so a
    # misspelled profile name stops the run without touching the disk.
    try {
        $Exclusions = Get-ExclusionProfile -Name $ExclusionProfile
    }
    catch {
        $Result.Message = $_.Exception.Message
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

    # Build Robocopy's exclusion switches from the profile(s).
    #   /XD <names>  excludes folders with these names at ANY depth.
    #   /XD <full paths> excludes only those exact folders. That's how
    #                top-level-only folders (RootDirectories) are handled:
    #                "Library" becomes "C:\...\MyGame\Library".
    #   /XF <patterns> excludes matching files anywhere.
    # A switch is only added if it has something to exclude.
    $FullSource = Get-FullPath $Source
    $ExcludedDirectories = @($Exclusions.Directories) +
        @($Exclusions.RootDirectories | ForEach-Object { Join-Path $FullSource $_ })
    $ExcludedFiles = @($Exclusions.Files)

    $ExclusionOptions = @()
    if ($ExcludedDirectories.Count -gt 0) {
        $ExclusionOptions += "/XD"
        $ExclusionOptions += $ExcludedDirectories
    }
    if ($ExcludedFiles.Count -gt 0) {
        $ExclusionOptions += "/XF"
        $ExclusionOptions += $ExcludedFiles
    }

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

    # Where this project's Git bundle goes (see "Git bundle" below), and
    # whether one is already there from an earlier run.
    $IsGitRepository     = Test-Path -LiteralPath (Join-Path $Source ".git")
    $BundlePath          = Join-Path $Destination "$ProjectName.bundle"
    $BundleExistedBefore = Test-Path -LiteralPath $BundlePath

    Write-Host "Source:      $Source"
    Write-Host "Destination: $Destination"
    Write-Host "Exclusions:  $($Exclusions.Name)`n"

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
        $ExclusionOptions `
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

        # The bundle from an earlier run exists only in the backup, so
        # Robocopy counts it as an "extra" file. It belongs there, so it is
        # not counted, keeping "only in backup" about YOUR files.
        if ($BundleExistedBefore -and $Result.FilesExtra -gt 0) {
            $Result.FilesExtra--
        }

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

    # ------------------------------------------------------------------
    # Git bundle
    # ------------------------------------------------------------------

    # NordLocker does not sync files or folders whose names start with a
    # dot, so the .git folder never reaches the cloud. A Git BUNDLE packs the
    # repository's whole history (every commit, branch, and tag) into ONE
    # ordinary file, which NordLocker does sync. To restore from it:
    #     git clone <ProjectName>.bundle <FolderName>
    # Only committed work is in a bundle; uncommitted changes are still
    # backed up as normal files above.
    $BundleProblem = $null
    if ($IsGitRepository) {
        if ($DryRun) {
            Write-BackupLog -LogFile $LogFile -Message "Git bundle:  would be saved as $BundlePath"
        }
        elseif (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            $BundleProblem = "Git is not installed, so the Git history bundle could not be created."
        }
        elseif (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
            $BundleProblem = "The destination folder does not exist, so the Git history bundle could not be created."
        }
        else {
            # A repository with no commits yet has nothing to bundle.
            $FirstRef = git -C $Source for-each-ref --count=1 --format="%(refname)"
            if (-not $FirstRef) {
                Write-BackupLog -LogFile $LogFile -Message "Git bundle:  skipped (the repository has no commits yet)."
            }
            else {
                # --all includes every branch and tag. Git writes to a
                # temporary "<name>.bundle.lock" file and only replaces the
                # old bundle once the new one is complete, so a failure
                # never damages the previous bundle.
                # 2>&1 captures Git's messages so they can go into the log.
                $BundleOutput = git -C $Source bundle create $BundlePath --all 2>&1
                if ($LASTEXITCODE -ne 0) {
                    $BundleProblem = "The Git history bundle could not be created: $(($BundleOutput | Select-Object -Last 1))"
                }
                else {
                    # Check the new bundle is complete and readable.
                    $VerifyOutput = git -C $Source bundle verify $BundlePath 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        $BundleProblem = "The Git history bundle failed verification: $(($VerifyOutput | Select-Object -Last 1))"
                    }
                    else {
                        $Result.BundleFile = $BundlePath
                        $BundleSize = (Get-Item -LiteralPath $BundlePath).Length
                        Write-BackupLog -LogFile $LogFile -Message ("Git bundle:  {0} ({1}, verified)" -f $BundlePath, (Format-ByteSize $BundleSize))
                    }
                }
            }
        }

        if ($BundleProblem) {
            Write-BackupLog -LogFile $LogFile -Color Red -Message "ERROR: $BundleProblem"
        }
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
    # A missing Git bundle also counts as a failure: the files were copied,
    # but the project's history would not reach the cloud.
    if ($ExitCode -ge 8) {
        $Result.Message = "Backup encountered an error. Exit code: $ExitCode"
        Write-BackupLog -LogFile $LogFile -Color Red -Message "`n$($Result.Message)"
    }
    elseif ($BundleProblem) {
        $Result.Message = "Files were copied, but the Git history was not saved. $BundleProblem"
        Write-BackupLog -LogFile $LogFile -Color Red -Message "`n$($Result.Message)"
    }
    else {
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

    if ($LogFile) {
        Write-Host "Log file:    $LogFile"
    }

    return $Result
}

function Backup-GitRepository {
    <#
    .SYNOPSIS
        Finds every Git repository under a folder and backs up each one.

    .DESCRIPTION
        Searches -SearchPath for Git repositories (see Find-GitRepository) and
        runs Backup-DevelopmentProject for each one. Every repository keeps
        the same relative location under -DestinationRoot, for example:

            C:\Users\Me\source\repos\Games\SpaceGame
            ->  <DestinationRoot>\Games\SpaceGame

        One repository failing does not stop the others.

    .OUTPUTS
        One result object per repository (the same kind that
        Backup-DevelopmentProject returns).

    .EXAMPLE
        $Results = Backup-GitRepository -SearchPath "C:\Users\Me\source\repos" -DestinationRoot "C:\NordLocker\Development_Backups"
    #>
    param(
        # Folder to search for Git repositories.
        [Parameter(Mandatory = $true)]
        [string]$SearchPath,

        # Folder that receives one backup folder per repository.
        [Parameter(Mandatory = $true)]
        [string]$DestinationRoot,

        # How many folder levels below -SearchPath to search.
        [int]$MaxDepth = 4,

        # Preview every repository's backup without copying anything.
        [switch]$DryRun,

        # Exclusion profile(s) used for every repository found.
        # Run Get-ExclusionProfile to list them. Default: VisualStudio.
        [string[]]$ExclusionProfile = @("VisualStudio"),

        # Folder where each repository's log file is written.
        # Defaults to %LOCALAPPDATA%\DevelopmentBackup\Logs.
        [string]$LogDirectory = (Get-DefaultLogDirectory)
    )

    if (-not (Test-Path -LiteralPath $SearchPath -PathType Container)) {
        Write-Host "ERROR: Search folder does not exist: $SearchPath" -ForegroundColor Red
        return
    }

    # Check the profile name(s) once, up front, instead of failing the
    # same way for every repository.
    try {
        Get-ExclusionProfile -Name $ExclusionProfile | Out-Null
    }
    catch {
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    $FullSearchPath      = Get-FullPath $SearchPath
    $FullDestinationRoot = Get-FullPath $DestinationRoot

    Write-Host "`nSearching for Git repositories in $FullSearchPath ..." -ForegroundColor Cyan

    # @( ) always produces an array, even when 0 or 1 repositories are found,
    # so .Count and foreach behave the same in every case.
    $Repositories = @(Find-GitRepository -Path $FullSearchPath -MaxDepth $MaxDepth)

    # Leave out repositories that are inside the destination: those are
    # earlier BACKUPS (they contain .git too). Backing them up again would
    # create backups of backups.
    $Repositories = @($Repositories | Where-Object {
        -not (Test-IsSameOrInside -Path $_ -Folder $FullDestinationRoot)
    })

    if ($Repositories.Count -eq 0) {
        Write-Host "No Git repositories found." -ForegroundColor Yellow
        return
    }

    Write-Host "Found $($Repositories.Count) Git repository(s):"
    foreach ($Repository in $Repositories) {
        Write-Host "  $Repository"
    }

    # The part of each repository's path below the search folder, for
    # example "Games\SpaceGame". Used for the backup location and the table.
    $SearchPrefix = $FullSearchPath.TrimEnd('\')
    function Get-RelativePath([string]$FullPath) {
        $Relative = $FullPath.Substring($SearchPrefix.Length).TrimStart('\')
        if (-not $Relative) {
            # The search folder is itself a repository; use its own name.
            $Relative = Split-Path -Path $FullPath -Leaf
        }
        return $Relative
    }

    # Back up each repository. "foreach" collects every result object that
    # Backup-DevelopmentProject returns into $Results.
    # -DryRun:$DryRun passes our switch along exactly as it was given.
    $Results = foreach ($Repository in $Repositories) {
        $Destination = Join-Path $FullDestinationRoot (Get-RelativePath $Repository)
        Backup-DevelopmentProject -Source $Repository -Destination $Destination `
            -DryRun:$DryRun -ExclusionProfile $ExclusionProfile -LogDirectory $LogDirectory
    }
    $Results = @($Results)

    # ------------------------------------------------------------------
    # Overview (console only)
    # ------------------------------------------------------------------

    # @{ Label = ...; Expression = { ... } } is a CALCULATED COLUMN: the
    # table shows whatever the script block returns for each result ($_).
    Write-Host "`n===== Git repository backup overview =====" -ForegroundColor Cyan
    $Results | Format-Table -AutoSize `
        @{ Label = "Repository";  Expression = { Get-RelativePath $_.Source } },
        Success,
        @{ Label = "Copied";      Expression = { if ($null -ne $_.FilesCopied) { "{0} ({1})" -f $_.FilesCopied, (Format-ByteSize $_.BytesCopied) } } },
        FilesFailed,
        @{ Label = "Backup size"; Expression = { if ($null -ne $_.BackupBytes) { Format-ByteSize $_.BackupBytes } } },
        @{ Label = "Bundle";      Expression = { if ($_.BundleFile) { "yes" } elseif (-not $_.DryRun -and -not $_.Success) { "NO" } else { "-" } } },
        Message | Out-Host

    # [long]$null is 0, so repositories without numbers simply add nothing.
    $Succeeded   = @($Results | Where-Object { $_.Success }).Count
    $FilesCopied = ($Results | ForEach-Object { [long]$_.FilesCopied } | Measure-Object -Sum).Sum
    $BytesCopied = ($Results | ForEach-Object { [long]$_.BytesCopied } | Measure-Object -Sum).Sum
    if ($DryRun) { $Verb = "would be copied" } else { $Verb = "copied" }

    if ($Succeeded -eq $Results.Count) { $Color = "Green" } else { $Color = "Red" }
    Write-Host ("{0} of {1} repository(s) succeeded. {2} file(s) {3} ({4})." -f `
        $Succeeded, $Results.Count, $FilesCopied, $Verb, (Format-ByteSize $BytesCopied)) -ForegroundColor $Color

    if (-not $DryRun) {
        $BackupBytes = ($Results | ForEach-Object { [long]$_.BackupBytes } | Measure-Object -Sum).Sum
        Write-Host ("Backups now use {0} in total." -f (Format-ByteSize $BackupBytes))
    }

    return $Results
}
