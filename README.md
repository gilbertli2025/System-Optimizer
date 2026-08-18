# System Optimizer

A single Windows GUI that tunes performance and hardens security — everything
is selectable and **restorable to defaults**.

## Download

[![Download](https://img.shields.io/badge/Download-v1.3.0-brightgreen)](https://github.com/gilbertli2025/System-Optimizer/releases/latest)

Get the portable package (`System-Optimizer-v1.3.0.zip`) from the
[Releases page](https://github.com/gilbertli2025/System-Optimizer/releases).

## Features

**Performance & Services** — disable safe/optional Windows services (telemetry,
Xbox, Fax, Remote Registry, Error Reporting, etc.) with backup and one-click
restore.

**Security & Hardening** — 10 items, each reversible:
1. Defender cloud protection (block at first sight)
2. Firewall: block all unsolicited inbound
3. Daily Defender quick scan at 03:00
4. Auto-lock screen after 10 min idle
5. Harden Edge + Chrome browsers
6. Enable System Restore + weekly restore points
7. BitLocker on C: (TPM)
8. Disable AutoRun on removable drives
9. Account lockout (5 tries / 15 min)
10. Block Office macros from the internet + disable Windows Script Host

**Maintenance & Cleanup** — temporary-file cleanup, Windows Update cleanup,
SSD trim, DNS flush, Game DVR, Storage Sense, recycle-bin, browser cache,
startup apps, visual effects, Fast Startup, tips, power plan.

**System Repair** — `sfc /scannow`, `DISM /restorehealth`, `chkdsk C: /f`.

**Master buttons** — Apply ALL selected · Restore ALL to defaults · Full
review/verify · Help (in-app settings guide).

## Requirements

- Windows 10 / 11 (64-bit). .NET 4.7.2+ (default on these systems).
- Some items (BitLocker, System Restore) need Windows Pro/Enterprise + TPM.
- On Windows 11, turn off **Smart App Control** if the exe is blocked
  (Windows Security → App & browser control → Smart App Control → Off).

## How to run

- Double-click `1-Click-System-Optimizer.cmd` (installs the signing cert and
  launches the GUI), or
- Run `SystemOptimizer.exe` directly (it self-elevates via UAC), or
- Install `System-Optimizer.msi`.

Tick what you want, click **Apply ALL selected**, then reboot. Use
**Restore ALL to defaults** to roll everything back.

## Backups / data

- Services: `%ProgramData%\WinServiceOpt\services-backup.csv`
- Security: `%ProgramData%\WinSecOpt\backup.json`
- Maintenance: `%ProgramData%\SystemOptimizer\maintenance-backup.json`
- Log: `%ProgramData%\SystemOptimizer\unified.log`

All backup files are written as **UTF-8 without BOM** so the JSON parses
reliably on every Windows PowerShell version. The Apply/Restore pipeline
saves a backup BEFORE every change and keeps the backup file if any single
restore step fails (so you can retry without losing data).

## Source layout

| Path | Purpose |
|------|---------|
| `1-Click-System-Optimizer.cmd` | One-click launcher (cert + GUI) |
| `SystemOptimizer-GUI.ps1` | The unified GUI app (thin shim) |
| `WinServiceOptimizer.ps1` / `-GUI.ps1` | Standalone services optimizer |
| `WinSecurityOptimizer.ps1` / `-GUI.ps1` | Standalone security optimizer |
| `lib/*.ps1` | Shared library — single source of truth for every setting |
| `lib/Common.ps1` | Paths, logging, JSON helpers, admin checks |
| `lib/ServiceCatalog.ps1` | Service list + Apply/Restore/Verify |
| `lib/SecurityItems.ps1` | 10 security items + Apply/Restore |
| `lib/MaintenanceItems.ps1` | 13 maintenance items + Apply/Restore |
| `lib/Repair.ps1` | sfc / DISM / chkdsk |
| `lib/Review.ps1` | Security review report |
| `SystemOptimizer.wxs` | WiX installer source (unified app) |
| `WindowsServicesOptimizer.wxs` | WiX installer source (services tool) |
| `WindowsSecurityOptimizer.wxs` | WiX installer source (security tool) |
| `build.ps1` | Compile + sign + build installers |
| `paths.json.example` | Tool locations, sign thumbprint |
| `tests/Lib.Tests.ps1` | Pester tests for the shared library |
| `PSScriptAnalyzerSettings.psd1` | Lint rules for the project |
| `.editorconfig` | Formatting rules (PowerShell, Markdown, JSON, WiX) |

## Building from source

```powershell
Install-Module -Name PS2EXE -Scope CurrentUser
# Install WiX Toolset v3 (candle.exe / light.exe) from https://wixtoolset.org

# Tool locations are picked up in this order:
#   1. -Ps2ExeModule / -WixBin / -SignThumbprint parameters to build.ps1
#   2. $env:WSO_PS2EXE / $env:WSO_WIX / $env:WSO_SIGN_THUMBPRINT
#   3. Copy paths.json.example to paths.json next to build.ps1
.\build.ps1
```

`build.ps1` compiles each `.ps1` to a `.exe` with PS2EXE, signs it with the
configured thumbprint (skip if empty), assembles the MSI installers via WiX,
and copies `HELP.md`, `README.md`, `1-Click-System-Optimizer.cmd` and the
`lib\` folder into the output directory so the install is self-contained.

## Testing

```powershell
Install-Module -Name Pester -Force -SkipPublisherCheck
Invoke-Pester ./tests
```

The tests mock every OS-touching cmdlet so they run anywhere with no admin
rights and no real changes to the system.

## License

Released under the [MIT License](LICENSE).

## Disclaimer

Provided as-is for your own machines. Changes are backed up and restorable,
but you are responsible for testing on a non-critical PC first. See `HELP.md`
for detailed explanations of every setting.
