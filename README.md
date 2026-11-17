# NordLocker_Robocopy

A PowerShell script that copies software development projects into NordLocker (or any backup folder) using Windows' built-in Robocopy. It keeps what matters — source code, assets, project files, and full Git history — and skips build output and temporary files that are easy to rebuild and waste sync bandwidth.

NordLocker does not read `.gitignore`, so this script decides what to leave out instead.

## Features

- **Keeps Git history** — the `.git` folder is copied in full, so commits, branches, tags, and repository settings survive.
- **Skips generated files** — Visual Studio and build output folders and per-user files are excluded (see [What gets excluded](#what-gets-excluded)).
- **Never deletes anything** — files that exist only in the backup are left alone. The script does not use Robocopy's `/MIR` or `/PURGE`.
- **Never touches the original project** — the source folder is only read.
- **Dry-run mode** — preview exactly what would be copied, without copying or creating anything.
- **Per-run log files** — every run (backup, dry run, or failed run) is recorded with Robocopy's full report.
- **Returns a result object** — scripts can check `.Success` instead of reading console text.
- **Backup summaries** — files copied, skipped, and failed, how much data was copied, and how much storage the backup uses.
- **Git discovery** — point it at a folder such as `source\repos` and it finds and backs up every Git repository inside, with an overview table at the end.
- **Exclusion profiles** — built-in exclusion lists for Visual Studio, Unity, Unreal, CMake, and Godot projects, which can be combined.
- **Git history that survives NordLocker** — each Git repository's full history is also saved as a single `.bundle` file, because NordLocker doesn't sync the `.git` folder (see [Git history and NordLocker](#git-history-and-nordlocker-bundles)).
- **Integrity verification** — check a backup against the original at any time: missing, changed, and damaged files, plus the Git bundle and `.git` copy.

## Requirements

- Windows 10 or 11 (Robocopy is built in)
- Windows PowerShell 5.1 or PowerShell 7+ (tested on both)

- [Git for Windows](https://git-scm.com/) — used to create the history bundles for Git repositories

No PowerShell modules are needed.

## Getting started

The script defines a PowerShell **function**. Load it into your current PowerShell session by *dot-sourcing* it (note the leading `.` and space):

```powershell
cd C:\Users\<you>\source\repos\DevelopmentBackup
. .\Backup-DevelopmentProject.ps1
```

The functions stay available until you close that PowerShell window:

| Command | What it does |
|---|---|
| `Backup-DevelopmentProject` | Backs up one project folder. |
| `Backup-GitRepository` | Finds every Git repository under a folder and backs up each one. |
| `Find-GitRepository` | Lists the Git repositories under a folder (copies nothing). |
| `Test-DevelopmentBackup` | Checks a backup against the original project (changes nothing). |
| `Get-ExclusionProfile` | Lists the exclusion profiles. |

> If PowerShell refuses to run the script because of its *execution policy*, see Microsoft's [about_Execution_Policies](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_execution_policies) page.

## Usage

**Back up a project:**

```powershell
Backup-DevelopmentProject `
    -Source "C:\Projects\CalculatorApp" `
    -Destination "C:\NordLocker\Development_Backups\CalculatorApp"
```

**Preview first (recommended for a new destination):**

```powershell
Backup-DevelopmentProject `
    -Source "C:\Projects\CalculatorApp" `
    -Destination "C:\NordLocker\Development_Backups\CalculatorApp" `
    -DryRun
```

**Write the log somewhere else:**

```powershell
Backup-DevelopmentProject `
    -Source "C:\Projects\CalculatorApp" `
    -Destination "C:\NordLocker\Development_Backups\CalculatorApp" `
    -LogDirectory "D:\BackupLogs"
```

**Check the result from a script:**

```powershell
$Result = Backup-DevelopmentProject -Source "C:\Projects\CalculatorApp" -Destination "C:\NordLocker\Development_Backups\CalculatorApp"

if (-not $Result.Success) {
    Write-Warning "Backup failed: $($Result.Message) (see $($Result.LogFile))"
}
```

**Back up several projects and list any failures:**

```powershell
$Projects = "C:\Projects\CalculatorApp", "C:\Projects\SpaceGame"

$Results = foreach ($Project in $Projects) {
    $Name = Split-Path $Project -Leaf
    Backup-DevelopmentProject -Source $Project -Destination "C:\NordLocker\Development_Backups\$Name"
}

$Results | Where-Object { -not $_.Success } | Format-Table Source, ExitCode, Message
```

**Built-in help:**

```powershell
Get-Help Backup-DevelopmentProject -Full
Get-Help Backup-GitRepository -Full
```

### Parameters

| Parameter | Required | Description |
|---|---|---|
| `-Source` | Yes | The project folder to back up. Must already exist. |
| `-Destination` | Yes | Where the backup goes. Created automatically if it doesn't exist (except during a dry run). |
| `-DryRun` | No | Lists what would be copied without copying, overwriting, or creating anything. Uses Robocopy's `/L` (list only) switch. |
| `-ExclusionProfile` | No | Which generated files to leave out: `VisualStudio` (default), `Unity`, `Unreal`, `CMake`, `Godot`, or several separated by commas. See [What gets excluded](#what-gets-excluded-exclusion-profiles). |
| `-LogDirectory` | No | Folder for log files. Defaults to `%LOCALAPPDATA%\DevelopmentBackup\Logs` (see [Logs](#logs)). |

### Result object

Every run returns one object. If you don't save it in a variable, PowerShell prints it at the end as a summary. To hide it, use `$null = Backup-DevelopmentProject ...`.

| Property | Description |
|---|---|
| `Success` | `$true` if the run worked (Robocopy exit code 0–7), otherwise `$false`. |
| `ExitCode` | Robocopy's exit code. Empty if Robocopy never ran (for example, the source was missing). |
| `DryRun` | `$true` if this was a dry run. |
| `ExclusionProfile` | The exclusion profile(s) used. |
| `FilesCopied` | Files copied (in a dry run: files that *would* be copied). |
| `BytesCopied` | Size of those files, in bytes. |
| `FilesSkipped` | Files not copied because they were unchanged, **or** excluded by a file pattern (`*.user`, `*.suo`, `*.cache`). Files inside excluded folders aren't counted at all. |
| `FilesFailed` | Files that could not be copied (for example, locked by another program). |
| `FilesExtra` | Files that exist only in the backup and were left alone. |
| `BackupFiles` | Number of files in the backup folder after the run, including `.git`. Empty for dry runs. |
| `BackupBytes` | Storage the backup folder uses after the run, in bytes. Empty for dry runs. |
| `BundleFile` | Path of the Git history bundle created this run. Empty for dry runs, folders that aren't Git repositories, and repositories with no commits yet. |
| `Duration` | How long the run took. |
| `Source` | The source path that was used. |
| `Destination` | The destination path that was used. |
| `LogFile` | Full path to this run's log file. Empty if logging failed. |
| `Message` | A short description of what happened. |

The run stops early, with `Success = $false`, if:

- the source folder doesn't exist,
- the destination is the source itself or inside it (Robocopy would otherwise copy the backup into itself), or
- the destination folder can't be created (for example, a missing drive, or part of the path is a file).

## Backing up all Git repositories at once

**See which repositories would be backed up:**

```powershell
Find-GitRepository -Path "C:\Users\<you>\source\repos"
```

**Preview, then back up all of them:**

```powershell
$Results = Backup-GitRepository `
    -SearchPath "C:\Users\<you>\source\repos" `
    -DestinationRoot "C:\NordLocker\Development_Backups" `
    -DryRun

$Results = Backup-GitRepository `
    -SearchPath "C:\Users\<you>\source\repos" `
    -DestinationRoot "C:\NordLocker\Development_Backups"
```

Each repository keeps its place in the folder layout, so repositories with the same name in different folders never collide:

```
C:\Users\<you>\source\repos\Games\SpaceGame   ->  C:\NordLocker\Development_Backups\Games\SpaceGame
C:\Users\<you>\source\repos\Tools\Calc        ->  C:\NordLocker\Development_Backups\Tools\Calc
```

At the end you get an overview table:

```
Repository                 Success Copied        FilesFailed Backup size Bundle Message
----------                 ------- ------        ----------- ----------- ------ -------
3D_Transformation_Pipeline    True 50 (139.6 KB)           0 175.4 KB    yes    Backup completed successfully!
DevelopmentBackup             True 76 (155.1 KB)           0 176.7 KB    yes    Backup completed successfully!
2 of 2 repository(s) succeeded. 126 file(s) copied (294.7 KB).
Backups now use 352.1 KB in total.
```

`$Results` holds one [result object](#result-object) per repository. Save the output in a variable as shown; otherwise PowerShell also prints every result object in full after the table.

| Parameter | Required | Description |
|---|---|---|
| `-SearchPath` | Yes | Folder to search for Git repositories. |
| `-DestinationRoot` | Yes | Folder that receives one backup folder per repository. |
| `-MaxDepth` | No | How many folder levels below `-SearchPath` to search. Default: `4`. |
| `-DryRun` | No | Preview every repository without copying anything. |
| `-ExclusionProfile` | No | Exclusion profile(s) for every repository found. Default: `VisualStudio`. |
| `-LogDirectory` | No | Where each repository's log file goes. Defaults to `%LOCALAPPDATA%\DevelopmentBackup\Logs`. |

How repositories are found:

- A folder is a repository if it contains `.git`.
- The search doesn't look inside a repository once it finds one. A repository nested inside another is backed up as part of the outer one.
- Folders that are links or junctions are skipped, so the search can't loop forever.
- Repositories inside `-DestinationRoot` are ignored, so earlier backups are never backed up again.
- Folders without `.git` are **not** backed up. Use `Backup-DevelopmentProject` for those.
- One repository failing doesn't stop the others.

## Git history and NordLocker (bundles)

**NordLocker does not sync files or folders whose names start with a dot.** That includes the `.git` folder, which holds a repository's entire history. This was confirmed by downloading a backup from the NordLocker website: the source files were there, but `.git` and `.gitignore` were missing. The copy in the local NordLocker folder still has them, but the cloud copy doesn't.

So for every Git repository, the script also saves a **Git bundle**: one ordinary file containing every commit, branch, and tag.

```
Development_Backups\SpaceGame\
    SpaceGame.bundle      <- full Git history, synced by NordLocker
    .git\                 <- full history too, but only on this PC
    Assets\ ...
```

**To restore a project from the cloud copy**, download its folder and run:

```powershell
git clone SpaceGame.bundle SpaceGame
```

That produces a complete repository with all branches, tags, and history, including `.gitignore` and any other committed dot-files. The clone's `origin` remote points at the bundle file. To point it back at GitHub:

```powershell
git remote set-url origin https://github.com/<you>/SpaceGame.git
```

Details:

- The bundle is refreshed on every real backup and checked with a **test restore**: it's cloned into a temporary folder, checked with `git fsck`, and the temporary copy is deleted. (`git bundle verify` alone isn't enough, because it only reads the bundle's header. A bundle cut in half still passes it.) Dry runs don't create or change the bundle.
- Git builds the new bundle in a temporary file first, so a failed run never damages the previous bundle.
- If the bundle can't be created, the run reports `Success = $false`. The files were still copied, but the history wouldn't reach the cloud.
- A bundle holds **committed** work only. Uncommitted changes are backed up as normal files, unless their names start with a dot.
- Folders that aren't Git repositories get no bundle. Repositories with no commits yet are skipped, because Git can't bundle an empty history.
- The bundle exists only in the backup, so Robocopy sees it as a backup-only file. The script leaves it out of the "only in backup" count.

## Checking a backup (integrity verification)

`Test-DevelopmentBackup` compares a backup with the original project and reports what it finds. It only **reads**: nothing in the original or the backup is changed.

**Check one project:**

```powershell
Test-DevelopmentBackup -Source "C:\Projects\SpaceGame" -Destination "C:\NordLocker\Development_Backups\SpaceGame"
```

If the backup was made with a profile other than the default, pass the same `-ExclusionProfile`. Otherwise excluded files look "missing".

**Check every backup you just made:** pipe the backup results straight in.

```powershell
$Results = Backup-GitRepository -SearchPath "C:\Users\<you>\source\repos" -DestinationRoot "C:\NordLocker\Development_Backups"
$Results | Test-DevelopmentBackup
```

**Check existing backups later, without copying anything:** a dry run produces the same list of projects.

```powershell
Backup-GitRepository -SearchPath "C:\Users\<you>\source\repos" -DestinationRoot "C:\NordLocker\Development_Backups" -DryRun | Test-DevelopmentBackup
```

Example (from a real check of two NordLocker backups):

```
Project                    Status   FilesChecked FilesMissing FilesChanged FilesDamaged GitBundle GitCopy
-------                    ------   ------------ ------------ ------------ ------------ --------- -------
3D_Transformation_Pipeline OK                 50            0            0            0 OK        OK
DevelopmentBackup          Outdated           80            0            2            0 OK        OK
```

### What is checked

Every file that should be in the backup (the same exclusion rules as the backup) is compared with the original using a **SHA-256 hash**, a fingerprint of the file's content that changes completely if even one bit differs. Differences are sorted using the files' timestamps. Robocopy copies each file's "last modified" time exactly, so:

| Group | Meaning |
|---|---|
| **Missing** | In the original but not in the backup (new since the last backup, or the copy failed). |
| **Changed** | Content and timestamp both differ: the original was edited after the last backup. |
| **Damaged** | Content differs but the timestamp is identical: the backup copy itself was altered or corrupted. |
| **Only in backup** | Files that exist only in the backup. Informational, never a problem. |

For Git repositories it also checks:

- **Git bundle:** a real test restore succeeds, and the bundle contains every current branch and tag.
- **Git copy (`.git`):** the backup's `.git` folder passes `git fsck`.

### Status

| Status | Meaning | What to do |
|---|---|---|
| `OK` | The backup matches the original exactly. | Nothing. |
| `Outdated` | Nothing is damaged, but the original has changed since the last backup. | Run the backup again. |
| `Damaged` | Part of the backup is corrupt. The log lists the affected files. | Delete the damaged files from the backup, then run the backup again. (Robocopy skips files whose size and date look unchanged, so it may not replace a damaged copy by itself.) |
| `Error` | The check couldn't run, for example because a folder doesn't exist or a profile name is wrong. | Read the message. |

Each run returns a result object (`Status`, `Success`, which is `$true` only for `OK`, the counts, the file lists `MissingFiles`/`ChangedFiles`/`DamagedFiles`/`ExtraFiles`, `GitBundle`, `GitCopy`, and `LogFile`) and writes a `..._VERIFY.log` file listing every affected file.

Notes:

- In a Git repository, any Git command (commit, fetch, …) updates files inside `.git`, so the backup shows as `Outdated` until the next backup. That's expected.
- `-Quick` compares only file sizes and dates. It's much faster for large projects but **can't detect damaged files**.
- Reading a file in the NordLocker folder that is stored only in the cloud makes NordLocker download it first. A full check of a large backup may download a lot of data.

## What gets excluded (exclusion profiles)

What's left out depends on the **exclusion profile**: a named set of generated folders and files for one kind of development environment. The default is `VisualStudio`, which is the same list this script has always used.

| Profile | Folders excluded at any depth | Folders excluded only at the top of the project | Files excluded |
|---|---|---|---|
| `VisualStudio` *(default)* | `.vs`, `x64`, `Debug`, `Release`, `bin`, `obj` | — | `*.user`, `*.suo`, `*.cache` |
| `Unity` | `.vs` | `Library`, `Temp`, `Obj`, `Build`, `Builds`, `Logs`, `UserSettings`, `MemoryCaptures`, `Recordings` | `*.csproj`, `*.sln`, `*.suo`, `*.user`, `*.pidb`, `*.booproj`, `*.svd`, `*.pdb`, `*.mdb`, `*.opendb`, `*.VC.db` |
| `Unreal` | `.vs`, `Binaries`, `Intermediate`, `DerivedDataCache` | `Saved` | `*.sln`, `*.suo`, `*.user`, `*.VC.db`, `*.opensdf`, `*.sdf` |
| `CMake` | `.vs`, `cmake-build-*` | `build`, `out` | — |
| `Godot` | — | `.godot`, `.import` | — |

**Choose a profile with `-ExclusionProfile`:**

```powershell
Backup-DevelopmentProject -Source "C:\Projects\SpaceGame" -Destination "C:\NordLocker\Development_Backups\SpaceGame" -ExclusionProfile Unity
```

**Combine profiles** by separating them with commas. Their lists are merged:

```powershell
Backup-DevelopmentProject -Source "C:\Projects\SpaceGame" -Destination "C:\NordLocker\Development_Backups\SpaceGame" -ExclusionProfile Unity, VisualStudio
```

**List the profiles** from PowerShell:

```powershell
Get-ExclusionProfile
```

How matching works:

- **Any depth:** a folder with that name is skipped wherever it is. Both `Debug\` and `src\Debug\` are skipped. Wildcards such as `cmake-build-*` are allowed.
- **Top of the project only:** only that exact folder is skipped. With `Unity`, the top-level `Logs\` is skipped but `Assets\Art\Logs\` is kept, because names like `Logs` and `Build` are also common for real content.
- **Files:** matching files are skipped anywhere. A *file* called `Debug.md` is still copied, because folder exclusions only apply to folders.
- `.git` is never excluded by any profile.
- The `Unreal` profile skips the top-level `Saved` folder, which includes the editor's autosaves. If you want those kept, remove `Saved` from the profile.
- A misspelled profile name stops the run before anything is created, and the error lists the valid names.

To add or change a profile, edit `$AllProfiles` in the `Get-ExclusionProfile` function in the script.

## How backups behave

This is an **incremental copy**, not a versioned backup:

- New files are copied.
- Files that changed in the project **overwrite** the older copy in the backup. Earlier versions are not kept (Git history inside `.git` is still preserved).
- Unchanged files are skipped, so repeat runs are fast.
- Files that exist only in the backup are reported as `*EXTRA File` and left in place.

## Logs

Each run creates a log file named after the project folder and the start time. By default, logs go to `%LOCALAPPDATA%\DevelopmentBackup\Logs`, which is usually `C:\Users\<you>\AppData\Local\DevelopmentBackup\Logs`:

```
CalculatorApp_2026-11-17_16-16-43.log
CalculatorApp_2026-11-17_16-16-57_DRYRUN.log
```

To open the folder:

```powershell
explorer "$env:LOCALAPPDATA\DevelopmentBackup\Logs"
```

The path of each run's log is also printed at the end of the run and stored in the result's `LogFile` property.

A log contains:

1. A header with the time, mode, source, and destination
2. Robocopy's full report: every new and changed file, the exclusions, and a totals table
3. The Robocopy exit code
4. A summary, the backup's size, the duration, and the final result:

```
Summary: 39 file(s) copied (6.03 MB), 1 skipped (unchanged or excluded by a file pattern), 0 failed, 0 only in backup.
Backup size: 39 file(s), 6.03 MB.
Duration:    0.2 seconds.
Backup completed successfully!
```

The summary lines are also shown in the console.

Notes:

- Logs are never written into the source project or the backup, and the default location is outside this project too, so backing up this project never copies its own logs.
- If the log can't be created, the script shows a warning and the backup still runs.
- If two runs of the same project start in the same second, they share one log file.
- Old logs are not deleted automatically.
- If you point `-LogDirectory` at a `Logs` folder inside this project, `.gitignore` keeps it out of Git.

## Exit codes

Robocopy's exit code is a set of flags added together. The script treats **0–7 as success** and **8 or higher as failure**.

| Code | Meaning |
|---|---|
| 0 | Nothing needed copying |
| 1 | Files were copied |
| 2 | Extra files exist only in the backup (left alone) |
| 3 | 1 + 2 |
| 4 | Mismatched files or folders were found |
| 8+ | Some files could not be copied — check the log |
| 16 | Fatal error; nothing was copied |

During a dry run, the code describes what *would* have happened.

## Known limitations

- Robocopy writes `100%` progress markers into the log file.
- Old logs build up over time and need removing by hand.
- The summary is read from Robocopy's English report. On a Windows installation where Robocopy reports in another language, the summary shows "not available" (the backup itself still works).
- Measuring the backup's size means listing every file in it, which can take a while for very large backups.
- A Git *worktree* (a folder whose `.git` is a file, not a folder) is found and backed up, but its history lives in the main repository, so back that up as well.
- NordLocker doesn't sync dot-named files and folders (`.git`, `.gitignore`, `.vscode`, `.editorconfig`, …). Committed ones come back from the Git bundle. **Uncommitted** dot-files and dot-files in projects that aren't Git repositories exist only in the local NordLocker folder, not in the cloud.

## Roadmap

| Feature | Status |
|---|---|
| Dry-run mode | ✅ Done |
| Logging | ✅ Done |
| Return a result object to the caller | ✅ Done |
| Git discovery — find repositories automatically | ✅ Done |
| Backup summaries — copied files and storage used | ✅ Done |
| Exclusion profiles for different environments | ✅ Done |
| Interactive project selection | Planned |
| Git history bundles (NordLocker doesn't sync `.git`) | ✅ Done |
| Integrity verification against the originals | ✅ Done |
| Multiple backup destinations | Planned |

## Author

Mr. Hardy
