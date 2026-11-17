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

The function stays available until you close that PowerShell window.

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

**Built-in help:**

```powershell
Get-Help Backup-DevelopmentProject -Full
```

### Parameters

| Parameter | Required | Description |
|---|---|---|
| `-Source` | Yes | The project folder to back up. Must already exist. |
| `-Destination` | Yes | Where the backup goes. Created automatically if it doesn't exist (except during a dry run). |
| `-DryRun` | No | Lists what would be copied without copying, overwriting, or creating anything. Uses Robocopy's `/L` (list only) switch. |
| `-LogDirectory` | No | Folder for log files. Defaults to a `Logs` folder next to the script. |

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

Each run creates a log file named after the project folder and the start time:

```
Logs\CalculatorApp_2026-11-17_16-16-43.log
Logs\CalculatorApp_2026-11-17_16-16-57_DRYRUN.log
```

A log contains:

1. A header with the time, mode, source, and destination
2. Robocopy's full report: every new and changed file, the exclusions, and a totals table
3. The Robocopy exit code and the final result

Notes:

- Logs are never written into the source project or the backup.
- If the log can't be created, the script shows a warning and the backup still runs.
- If two runs of the same project start in the same second, they share one log file.
- Old logs are not deleted automatically.
- The `Logs/` folder is excluded from Git by `.gitignore`.

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

- The function reports its result as console text only, so another script can't easily tell whether a backup succeeded.
- Robocopy writes `100%` progress markers into the log file.
- Old logs build up over time and need removing by hand.

## Roadmap

| Feature | Status |
|---|---|
| Dry-run mode | ✅ Done |
| Logging | ✅ Done |
| Return a result object to the caller | Planned |
| Git discovery — find repositories automatically | Planned |
| Backup summaries — copied files and storage used | Planned |
| Exclusion profiles for different environments | Planned |
| Interactive project selection | Planned |
| Integrity verification against the originals | Planned |
| Multiple backup destinations | Planned |

## Author

Mr. Hardy
