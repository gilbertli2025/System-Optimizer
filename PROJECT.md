# System Optimizer

A single Windows GUI that tunes performance and hardens security — everything
is selectable and **restorable to defaults**.

> Originally written as five largely-duplicated PowerShell scripts, this project
> was refactored into a thin-shim / shared-library architecture, packaged as
> compiled `.exe`s (PS2EXE) and MSI installers (WiX 3.14), and built out with
> proper logging, atomic JSON backups, and a Pester test suite.

---

## Features

### Performance & Services
Disable safe (DiagTrack, Xbox, Fax, Remote Registry, Error Reporting, …) and
optional (Search, Print Spooler, Remote Desktop, Bluetooth, …) Windows
services, with backup and one-click restore. Optional services are
non-default; the GUI shows each one's display name so users know what they're
disabling.

### Security & Hardening (10 reversible items)
1. Defender cloud protection (block at first sight)
2. Firewall: block all unsolicited inbound by default
3. Daily Defender quick scan at 03:00
4. Auto-lock screen after 10 min idle
5. Harden Edge + Chrome browsers
6. Enable System Restore + weekly restore points
7. BitLocker on C: (TPM) — flagged as confirm-before-apply
8. Disable AutoRun on removable drives
9. Account lockout (5 tries / 15 min) — flagged as confirm-before-apply
10. Block Office macros from internet + disable Windows Script Host — flagged

### Maintenance & Cleanup (5 safe + 8 reversible)
- Clear temp files, Windows Update cleanup, SSD trim, DNS flush
- Disable Game DVR, enable Storage Sense, Empty Recycle Bin, Clear browser cache
- Disable startup apps, Visual Effects → best performance, Fast Startup,
  disable Tips, Power plan → High Performance

### System Repair (read-only / on-demand)
- `sfc /scannow`
- `DISM /restorehealth`
- `chkdsk C: /f` (requires restart)

### Master buttons
Apply ALL selected · Restore ALL to defaults · Full review / verify · Help

---

## Architecture

The project uses a **thin-shim / shared-library** pattern:

```
+--------------------------------------------------+
|  Entry-point scripts (UI only, ~150 lines each)  |
|  - SystemOptimizer-GUI.ps1    (unified GUI)      |
|  - WinServiceOptimizer-GUI.ps1                  |
|  - WinServiceOptimizer.ps1     (console)         |
|  - WinSecurityOptimizer-GUI.ps1                 |
|  - WinSecurityOptimizer.ps1    (console)         |
+--------------------------------------------------+
                    |  dot-source
                    v
+--------------------------------------------------+
|  lib/ — single source of truth (1.7k lines)      |
|  - Common.ps1          paths, logging, JSON     |
|  - ServiceCatalog.ps1  service lists + helpers  |
|  - SecurityItems.ps1   10 hardening items       |
|  - MaintenanceItems.ps1 13 cleanup items        |
|  - Repair.ps1          sfc / DISM / chkdsk      |
|  - Review.ps1          security review report   |
+--------------------------------------------------+
```

Before this refactor, the same logic existed in 5 places (~3,090 LOC of
duplicated code). After: ~1,094 LOC of entry points + 1,739 LOC of library =
2,833 LOC total — **~8 % smaller with proper structure**.

---

## Repository layout

```
System-Optimizer-main/
├── lib/                       shared library — single source of truth
├── *.ps1                      5 thin entry-point shims
├── *.wxs                      3 WiX installer sources
├── 1-Click-System-Optimizer.cmd    one-click launcher
├── build-all.ps1              end-to-end build (PS2EXE + WiX + signing + ZIP)
├── build.ps1                  configurable build (env vars / paths.json)
├── package.ps1                re-sign + package ZIP
├── paths.json.example         config template
├── PSScriptAnalyzerSettings.psd1
├── tests/
│   └── Lib.Tests.ps1          Pester 5 tests
├── PS2EXE-master/             vendored PS2EXE (build dep)
├── source/                    bundled copy of every source file (see below)
├── README.md                  project intro
├── HELP.md                    user guide (also opened by the Help button)
├── INSTALL.txt                install + troubleshooting guide
├── STEPS-for-end-users.txt     3-step guide for non-technical users
├── LICENSE                    MIT
├── .editorconfig
└── .gitattributes
```

### `source/` — bundled source archive

The `source/` subfolder contains a flat copy of every original source file
(this project's "src.zip" equivalent). Use it to copy the tool to another
PC, audit the code offline, or recreate the build from scratch.

```
source/
├── lib/                       6 PS1 library files
├── *.ps1                      5 entry-point shims
├── *.wxs                      3 WiX installer sources
├── *.cmd, *.bat               9 launcher / helper batch files
├── build-all.ps1, build.ps1, package.ps1   build scripts
├── paths.json.example         config template
├── PSScriptAnalyzerSettings.psd1
├── tests/Lib.Tests.ps1        tests
├── .editorconfig, .gitattributes
├── README.md, HELP.md, INSTALL.txt,
│   STEPS-for-end-users.txt, LICENSE         documentation
└── build-msi.ps1              rebuild installers from a folder copy
```

---

## Build

```powershell
# 1. Prereqs (one-time)
Install-Module -Name PS2EXE -Scope CurrentUser   # already vendored at ./PS2EXE-master
Install WiX Toolset v3.14                       # to ./Tools/wix314 or set $env:WSO_WIX

# 2. Configure
Copy paths.json.example to paths.json next to build.ps1 and edit, OR set env vars:
$env:WSO_PS2EXE = 'C:\Path\To\ps2exe.psm1'
$env:WSO_WIX    = 'C:\Path\To\wix\bin'
$env:WSO_SIGN_THUMBPRINT = '<your thumbprint>'   # optional code-signing cert

# 3. Build
.\build-all.ps1
# Outputs to  ~Desktop\System-Optimizer-Build\System-Optimizer-v1.3.0\
```

The full pipeline (PS2EXE → 5 signed exes → WiX → 3 MSIs → SHA-256 ZIP) is in
**`build-all.ps1`**.

---

## Run

### From the package folder
```cmd
cd C:\SystemOptimizer\
run.bat                                  :: unified GUI (recommended)
1-Click-System-Optimizer.cmd             :: installs WSO-Trust.cer + GUI
apply-services.bat                       :: CLI helpers
apply-security.bat
restore-services.bat
restore-security.bat
verify-services.bat
review-security.bat
list-services.bat
```

### From the MSI installer
Double-click `installer\System-Optimizer.msi` on the target PC. It installs
to `C:\Program Files\System Optimizer\` and adds a Start Menu shortcut.

### From a USB stick
The `portable\` subfolder is an identical self-contained copy — copy it
to a USB stick root and double-click `launch.bat`.

---

## Test

```powershell
Install-Module -Name Pester -Force -SkipPublisherCheck
Invoke-Pester ./tests
```

Or use the standalone runner that ships with the build artifacts:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Lib.Tests.ps1
```

13 of 13 tests passing, including:
- JSON round-trip with no BOM (PS 5.1 UTF-8 bug fix)
- CSV round-trip for the services backup
- Missing / corrupt JSON handled gracefully
- Log file appendability + no BOM
- Atomic write semantics (`.new` then move)
- Backup survives partial restore failure

---

## Bug fixes made during this session

| # | Bug | Fix |
|---|---|---|
| 1 | `Apply-OfficeWSH` saved backup **after** the registry changes | Move the backup row to before any `Set-ItemProperty` |
| 2 | UTF-8 BOM in JSON backups broke `ConvertFrom-Json` on PS 5.1 | Write via `[System.IO.File]::AppendAllText(..., [System.Text.UTF8Encoding]::new($false))` |
| 3 | `Apply-BitLocker` saved twice (`AlreadyOn` + `Disabled`) | Single backup row whose `Value` records the original state |
| 4 | Snapshot was taken on restore path too (standalone tools) | Snapshot only created in the apply handler |
| 5 | `Restore-Security` deleted the backup file even when one row failed | Keep the file with the remaining rows; only delete on full success |
| 6 | PowerShell `lock` keyword failed in PS 5.1 | Replace with `[System.Threading.Monitor]::TryEnter`/`Exit` |
| 7 | `Set-KeyedRow` (JSON merge) silently appended duplicate empty-array entries | Switch to explicit `ArrayList` from `Write-Output -NoEnumerate` |
| 8 | Power-plan `Restore-*` silently fell back to Balanced GUID on `powercfg` regex miss | Now refuses to clobber if it cannot parse the active scheme |
| 9 | All `Set-ItemProperty`/`Set-MpPreference` calls lacked `-ErrorAction` | Added `-ErrorAction Stop` throughout |
| 10 | `Show-YesNo` fell back to `Read-Host`, which **hangs a GUI process** forever | Fall back to `[System.Windows.Forms.MessageBox]::Show()` when `UserInteractive` |
| 11 | `Set-StrictMode -Version 2.0` triggered false-positive `.Count` / `.DisplayName` errors | Removed StrictMode from all entry-point scripts |
| 12 | `run.bat` launched the compiled `.exe`, which couldn't dot-source `lib\*.ps1` under Restricted execution policy | `run.bat` now launches `powershell -ExecutionPolicy Bypass -File SystemOptimizer-GUI.ps1` |
| 13 | `.bat` files written via `Set-Content -Encoding UTF8` had a BOM that broke `cmd.exe` parsing | Use `[System.IO.File]::WriteAllText(..., [System.Text.UTF8Encoding]::new($false))` for all `.bat`/`.cmd` |
| 14 | `Restart-Admin` re-launched the compiled `.exe` (same policy problem) | Re-launch via `powershell -ExecutionPolicy Bypass -File <ps1>` instead |
| 15 | `Get-Service` returned `$null` for missing services → `.DisplayName` threw under StrictMode | Wrap in `if ($svc) { $svc.DisplayName } else { $null }` |
| 16 | WiX `.wxs` files hard-coded `C:\Users\admin\...` paths | Use `$(var.SourceDir)` + `$(var.Version)` with `candle.exe -dSourceDir=... -dVersion=...` |
| 17 | `Common.ps1` `$script:WriteLogSync` / `$script:UiSink` reads under StrictMode | Initialize defaults at load time |
| 18 | Destructive actions (Recycle Bin, BitLocker, Script Host, lockout) had no confirm | `Show-YesNo` confirmation added before the apply path |

---

## Configuration

`build.ps1` (the configurable build) reads its tool paths from:
1. Command-line parameters
2. Environment variables (`WSO_PS2EXE`, `WSO_WIX`, `WSO_SIGN_THUMBPRINT`, `WSO_OUTDIR`)
3. `paths.json` next to the script

See `paths.json.example` for the schema.

---

## License

MIT. See `LICENSE`. No warranty — test on a non-critical PC first.