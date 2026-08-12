# System Optimizer

A single Windows GUI that tunes performance and hardens security — everything
is selectable and **restorable to defaults**.

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
- Log: `%ProgramData%\SystemOptimizer\unified.log`

## Source layout

| File | Purpose |
|------|---------|
| `SystemOptimizer-GUI.ps1` | The unified GUI app (main source) |
| `WinServiceOptimizer.ps1` / `-GUI.ps1` | Standalone services-optimizer console/GUI sources |
| `WinSecurityOptimizer.ps1` / `-GUI.ps1` | Standalone security-optimizer console/GUI sources |
| `SystemOptimizer.wxs` | WiX installer source (unified app) |
| `WindowsServicesOptimizer.wxs` | WiX installer source (services tool) |
| `WindowsSecurityOptimizer.wxs` | WiX installer source (security tool) |
| `build.ps1` | Script that compiles, signs and builds the MSIs |

## Building from source

Run `.\build.ps1` after installing:
- **PS2EXE** (open source, GitHub: MScholtes/PS2EXE) — compiles `.ps1` → `.exe`
- **WiX Toolset v3** (`candle.exe` / `light.exe`) — builds the `.msi`

See the build script for the exact commands, including how to re-sign with your
own code-signing certificate.

## License

Released under the [MIT License](LICENSE).

## Disclaimer

Provided as-is for your own machines. Changes are backed up and restorable,
but you are responsible for testing on a non-critical PC first. See `HELP.md`
for detailed explanations of every setting.
