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

## Requirements

- Windows 10 or 11 (Robocopy is built in)
- Windows PowerShell 5.1 or PowerShell 7+ (tested on both)

No modules or other downloads are needed.

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
| `-LogDirectory` | No | Folder for log files. Defaults to `%LOCALAPPDATA%\DevelopmentBackup\Logs` (see [Logs](#logs)). |

### Result object

Every run returns one object. If you don't save it in a variable, PowerShell prints it at the end as a summary. To hide it, use `$null = Backup-DevelopmentProject ...`.

| Property | Description |
|---|---|
| `Success` | `$true` if the run worked (Robocopy exit code 0–7), otherwise `$false`. |
| `ExitCode` | Robocopy's exit code. Empty if Robocopy never ran (for example, the source was missing). |
| `DryRun` | `$true` if this was a dry run. |
| `FilesCopied` | Files copied (in a dry run: files that *would* be copied). |
| `BytesCopied` | Size of those files, in bytes. |
| `FilesSkipped` | Files not copied because they were unchanged, **or** excluded by a file pattern (`*.user`, `*.suo`, `*.cache`). Files inside excluded folders aren't counted at all. |
| `FilesFailed` | Files that could not be copied (for example, locked by another program). |
| `FilesExtra` | Files that exist only in the backup and were left alone. |
| `BackupFiles` | Number of files in the backup folder after the run, including `.git`. Empty for dry runs. |
| `BackupBytes` | Storage the backup folder uses after the run, in bytes. Empty for dry runs. |
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
Repository                 Success Copied        FilesFailed Backup size Message
----------                 ------- ------        ----------- ----------- -------
3D_Transformation_Pipeline    True 50 (139.6 KB)           0 139.6 KB    Backup completed successfully!
DevelopmentBackup             True 67 (103.3 KB)           0 112.2 KB    Backup completed successfully!
2 of 2 repository(s) succeeded. 117 file(s) copied (242.8 KB).
Backups now use 251.8 KB in total.
```

`$Results` holds one [result object](#result-object) per repository. Save the output in a variable as shown; otherwise PowerShell also prints every result object in full after the table.

| Parameter | Required | Description |
|---|---|---|
| `-SearchPath` | Yes | Folder to search for Git repositories. |
| `-DestinationRoot` | Yes | Folder that receives one backup folder per repository. |
| `-MaxDepth` | No | How many folder levels below `-SearchPath` to search. Default: `4`. |
| `-DryRun` | No | Preview every repository without copying anything. |
| `-LogDirectory` | No | Where each repository's log file goes. Defaults to `%LOCALAPPDATA%\DevelopmentBackup\Logs`. |

How repositories are found:

- A folder is a repository if it contains `.git`.
- The search doesn't look inside a repository once it finds one. A repository nested inside another is backed up as part of the outer one.
- Folders that are links or junctions are skipped, so the search can't loop forever.
- Repositories inside `-DestinationRoot` are ignored, so earlier backups are never backed up again.
- Folders without `.git` are **not** backed up. Use `Backup-DevelopmentProject` for those.
- One repository failing doesn't stop the others.

## What gets excluded

| Type | Excluded |
|---|---|
| Folders | `.vs`, `x64`, `Debug`, `Release`, `bin`, `obj` |
| Files | `*.user`, `*.suo`, `*.cache` |

Folder exclusions match by **name at any depth**. For example, both `Debug\` and `src\Debug\` are skipped. A *file* called `Debug.md` is still copied, because folder exclusions only apply to folders.

To change the lists, edit `$ExcludedDirectories` and `$ExcludedFiles` in the script.

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

## Roadmap

| Feature | Status |
|---|---|
| Dry-run mode | ✅ Done |
| Logging | ✅ Done |
| Return a result object to the caller | ✅ Done |
| Git discovery — find repositories automatically | ✅ Done |
| Backup summaries — copied files and storage used | ✅ Done |
| Exclusion profiles for different environments | Planned |
| Interactive project selection | Planned |
| Integrity verification against the originals | Planned |
| Multiple backup destinations | Planned |

## Author

Mr. Hardy
