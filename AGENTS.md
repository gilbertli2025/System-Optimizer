# Project memory: System Optimizer (v1.5)

Auto-loaded by opencode every session. Keep this brief and up to date.

## What this is
A Windows GUI tool (PowerShell + WinForms) that lets a normal user safely tune
performance and harden security, with everything reversible.

## Status
- Current version: **v1.5.0** (published on GitHub + a v1.5.0 Release).
- Refactored into modular `lib/`; 9/9 Pester tests pass, PSScriptAnalyzer 0 errors.
- This folder is the source + build output (exe + msi + lib here).
- GitHub repo: `github.com/gilbertli2025/System-Optimizer`; USB deploy at `D:\System-Optimizer`.
- C-drive workspace = DEV + build. D-drive USB = DELIVERABLES ONLY (no source) for testing on other PCs.

## Structure
- `SystemOptimizer-GUI.ps1` = UI shell (5 tabs); dot-sources `lib/*.ps1`:
  `Common.ps1` (paths, logging, JSON/CSV), `ServiceCatalog.ps1` (services),
  `SecurityItems.ps1` (10 hardening items), `MaintenanceItems.ps1` (13 items),
  `Repair.ps1` (sfc/dism/chkdsk), `Review.ps1` (security report),
  `BackupRestore.ps1` (backup/restore user settings + pre-flight).
- 5 tabs: Performance & Services, Security & Hardening, Maintenance & Cleanup,
  System Repair, Backup & Restore (blue tab strip for readability).
- `1-Click-System-Optimizer.cmd` runs `SystemOptimizer-GUI.ps1` via `powershell -Bypass`.
- `1-Click-System-Restore.cmd` + `SystemOptimizer-Restore.ps1` = one-click restore
  of user settings from the USB backup.
- `tests/Lib.Tests.ps1` (Pester). Run: `Invoke-Pester ./tests`.
- Sign cert thumbprint: `C2DD93EC094DEAD52F7C275007B646452A9D79A6`.

## Build (quick, one app)
```
# exe
ps2exe -inputFile SystemOptimizer-GUI.ps1 -outputFile SystemOptimizer.exe -title "System Optimizer" -version 1.3.0.0 -noConsole
# msi (WiX 3.x) - MUST pass the preprocessor vars
candle.exe SystemOptimizer.wxs "-dSourceDir=<this folder>" "-dVersion=1.3.0" -out so.wixobj
light.exe so.wixobj -out System-Optimizer.msi
```
Then sign exe + msi with the cert (see AGENTS gotchas on SAC).

## Gotchas / lessons learned
- JSON backups must be UTF-8 **no BOM** and read back as **flat arrays**
  (`Read-JsonArray` in `lib/Common.ps1`). Nested arrays corrupt restore.
- Batch (`.cmd`) launcher must use **CRLF** and no unescaped `&` in `title`.
- Self-signed exes are blocked by Windows 11 **Smart App Control**; prefer the
  `.ps1`-run launcher or disable SAC.
- WiX `.wxs` uses `$(var.Version)` / `$(var.SourceDir)` — pass
  `-dSourceDir` / `-dVersion` to candle or the MSI build fails.
- `build.ps1` needs `WSO_PS2EXE`, `WSO_WIX`, `WSO_THUMBPRINT` env vars set.
- **Compiled exe finds lib via the current working directory** (`$PSCommandPath` is empty in ps2exe). Always launch the exe from its own folder (launcher does `cd /d "%~dp0"`), or it fails to load `lib\Common.ps1`. The `.ps1` launcher is immune (uses `$PSCommandPath`).
- USB detection uses `[IO.DriveInfo]::new($d).DriveType` — **wmic is NOT installed** on modern Windows, so don't use it.
- A merged-line edit (no newline between two statements) is a silent runtime bug that parses fine — watch for `)$variable` concatenations when editing the GUI.
- The user is **not a programmer** — plan first, keep the tool safe/reversible
  for normal users, and verify generated code (it can have subtle bugs).

## Tooling available on this PC
- ps2exe module: `C:\Users\admin\AppData\Local\Temp\opencode\ps2exe\...\ps2exe.psm1`
- WiX: `C:\Users\admin\AppData\Local\Temp\opencode\wix` (candle.exe / light.exe)
- Pester 6.1 + PSScriptAnalyzer installed; sqlite3 installed.
- `read-image` skill: OCR screenshots (snipping tool) for debugging.

## v1.4 features (all done 2026-08-19)
- [x] Graceful admin check / error handling (no more crash).
- [x] Diagnostics: drive health (SMART), disk space, resource report, power/battery.
- [x] "Explain this" mode (plain-language item help).
- [x] Export/import settings profile.
- [x] Undo-last-run (session-based restore).
- [x] Smarter startup cleanup (safe whitelist).

## v1.5 (2026-08-20)
- [x] Scheduled auto-maintenance (weekly Task Scheduler: temp cleanup, DNS, SSD trim, quick scan).
- [x] Backup improvements: BitLocker recovery key included, Verify backup, auto-detect USB backup folder.
- [x] **Backup-first**: before Apply, creates a System Restore point + offers a USB settings backup.
- [x] **USB detection** via `[IO.DriveInfo]::new(drive).DriveType == "Removable"` (NOT wmic - not installed on modern Windows).
- [x] **1-Click-System-Restore** launcher: easy restore of bookmarks/Wi-Fi/settings from USB backup.
- [x] **1-Click-Restore hardening**: registry import no longer aborts restore (fails gracefully + safe).
- [x] **Pop-up UX**: all dialogs centered over the app; friendlier text ("click OK to continue, then switch tabs").
- [x] **Blue tab strip** via OwnerDrawFixed + ItemSize 158px (OwnerDrawNormal does NOT exist on PS 5.1/.NET Framework - only Normal | OwnerDrawFixed).
- [x] Fixed startup crash: two lines were merged on the Repair tab button (broke `.ps1` run; exe was a stale build).
- [ ] (later) duplicate finder, force uninstaller, driver checker.
- USB is the recommended way to run + back up settings (launcher prompts if not on USB).

## v1.7 (planned 2026-08-21) - more useful + professional (2-day plan)
Researched (PC Manager, DeepPurge, SysManager, Norton, etc.). Stay safe/reversible.
- [ ] **Startup Manager** (Utilities tab): list boot entries (Run/RunOnce keys + Startup folders); safe enable/disable via StartupApproved (reversible, like Task Manager); open file location.
- [ ] **Broken Shortcuts finder**: find dead .lnk, delete to Recycle Bin.
- [ ] **Drive Health (SMART)**: disk temp/wear/errors report, colour verdicts.
- [ ] **Network Repair**: DNS flush, Winsock reset, ipconfig renew.
- [ ] **System Health Check**: read-only scan giving a health summary + recommendations.
- [ ] Version bump to v1.7.0 + changelog.
- NOT adding (safety): registry cleaner, driver updater, RAM boost.

## USB deliverable layout (D:\System-Optimizer)
Only runnable files for end users (NO source/build files):
- `1-Click-System-Optimizer.cmd`, `1-Click-System-Restore.cmd`
- `SystemOptimizer-GUI.ps1`, `SystemOptimizer-Restore.ps1`, `SystemOptimizer.exe`, `System-Optimizer.msi`
- `lib\` (all 7 .ps1), `WSO-Trust.cer`, `HELP.md`, `README.md`, `STEPS-for-end-users.txt`, `RESTORE.txt`, `INSTALL.txt`
- Settings backup goes to `X:\SystemOptimizer-Backup\<COMPUTERNAME>\`.

## v1.6 (built 2026-08-21) - Crash-Proof Backup & Easy Recovery
**3 top-level tabs** (big blue, OwnerDraw): **Easy** | **Advanced** | **Utilities**. Click a tab to run that part.
- [x] **Version tab** (`What's new`): shows `v1.6.0`, build date, a changelog per version (`$script:AppVersion`/`$script:AppBuildDate`/`$script:Changelog` in the GUI), plus the USB-safety reminder. Top-right version label is clickable (blue, hand cursor) and jumps to the Version tab.
- **USB emphasis**: launcher + Version tab both tell the user to run only from the USB and keep it safe (it holds their backup + recovery key).
- [x] **Easy tab**: health card (free space / last backup / Defender) + big One-Click Optimize (backup settings+folders FIRST -> restore point -> safe recommended items, risky excluded) + Restore wizard (THIS/other PC, tick folders, optional specific-files picker).
- [x] **Advanced tab**: backup-reminder banner ("Back up now") + 5 sub-tabs (Performance, Security, Maintenance, Repair, Backup & Restore) + master buttons (Apply ALL etc.).
- [x] **Utilities tab**: duplicate finder (size->hash), disk analyzer, large-file finder (>100MB), programs-list export. All preview + Recycle-Bin safe (Remove-ToRecycleBin). Added "Keep newest" auto-select (keeps 1 per group) + "Open file folder" (double-click a result to jump to it in Explorer).
- [x] Removed all `continue`/`break` from FolderBackup.ps1 + Utilities.ps1 (Pester 6.1 bug #2669 mis-flag).
- [x] **Per-run log on USB** (`<USB>\logs\run-<PC>-<timestamp>.log`): every run writes its log to the USB (Write-Log also mirrors to `$script:RunLog`); keeps the newest **7** run logs (rotation before create, keeps 6 old + current). Helps troubleshooting. Not created when not on a removable drive.
- NOTE (Pester quirk): Pester 6.1 fails a multi-`It` test file in this workspace with "break/continue escaped" (bug #2669) even though each `It` passes on its own; it's a Pester env quirk, NOT an app bug. Tests live in `tests\Lib.Tests.ps1` (Common.ps1 only).
- NOTE (workspace cleanup): at some point the workspace lost `tests\Lib.Tests.ps1`, `WSO-Trust.cer`, `README.md`, `STEPS-for-end-users.txt`, `INSTALL.txt`, and lib `Repair.ps1`/`Review.ps1`/`ServiceCatalog.ps1`. Restored docs+lib from the USB; recreated the test file.
- [x] **User-folder backup** via robocopy (`lib\FolderBackup.ps1`): Documents/Pictures/Music/Videos/Downloads/Desktop -> `X:\SystemOptimizer-Backup\<PC>\files\...`, per-PC, incremental.
- [x] **Restore-UserSettings** now takes `-Source` (restore from a chosen backup folder).
- [x] Installed-programs list export (winget/registry -> InstalledPrograms.txt on USB).
- [x] Top tabs: native Windows-theme, auto-size (Segoe UI 11 bold). Sub-tabs: native, auto-size (Segoe UI 10 bold). NOTE: OwnerDraw blue tabs caused DPI scaling / proportion problems on some displays - reverted to NATIVE themed tabs for reliable proportion.
- USB-only (no cloud/2nd copy). Deliberately no registry cleaner/driver updater/boost (safety).

## Competitive comparison + add-on feasibility (researched 2026-08-20)
- Our edge vs System Mechanic / Glary / CCleaner / Advanced SystemCare / MS PC Manager:
  safe + reversible (undo/restore/restore point), portable USB, security hardening (10 items),
  no ads. They are aggressive cleaners; we are NOT (see stance below).
- Easy to add in our `lib\*.ps1`+GUI stack (proven by existing PowerShell tools): large-file finder,
  disk-space analyzer, duplicate-file finder (size->hash, Recycle-Bin safe), startup manager,
  programs-list export.
- Medium: uninstaller (winget/msiexec), driver-store cleanup (pnputil, previewed).
- Deliberately NOT (risky, matches MS PC Manager): registry cleaner, auto driver updater,
  RAM/process "boost", antivirus.
- Recommendation for later: duplicate finder, large-file finder, disk analyzer, programs-list export.

## v1.6 UI design (finalized 2026-08-20)
- **Two modes** in one window, top toggle: Easy (default on launch) | Advanced.
- **Easy**: health card + big One-Click Optimize (backup settings+folders FIRST -> restore point -> safe recommended items only) + Restore wizard (THIS PC / ANOTHER PC; tick folders; per-folder [Choose files...] to restore only selected files/sub-folders).
- **Advanced**: existing 5 tabs + top backup-reminder banner + new Utilities tab.
- **Utilities tab (4, preview-first + Recycle-Bin safe)**: duplicate finder, disk analyzer, large-file finder, programs-list export (saves InstalledPrograms.txt to USB).
- Easy mode never applies risky items (BitLocker/Office-macros/lockout); those stay in Advanced with confirm.

## Market position (2026-08-19)
- Competitors (MS PC Manager, CCleaner, BleachBit, Advanced SystemCare, Fortect) are
  mostly "aggressive cleaners": good junk cleanup, weak safety/reversibility, no real
  security hardening.
- Our edge: safe + fully reversible (backup/restore/undo-last), security hardening
  (10 items), educational (explain mode, reports), open-source + no adware/upsells.
- Gaps to close: scheduler, duplicate finder, driver updater, force uninstaller.

## Local LLM (Ollama, set up 2026-08-19)
- **Ollama** installed, API on `http://localhost:11434` (must be running to use).
- Model: **qwen2.5-coder:3b** (local, offline). Good for simple/private tasks; weak vs cloud.
- Helper: `ask-local.ps1` (temp opencode dir) - call it to delegate a prompt to the
  local model. The main agent orchestrates it; always review/fix the local model's output.
- Workflow: I (the agent) decide which sub-tasks to pass to the local model (simple script
  drafting, offline/private work) and ALWAYS verify/fix its output before presenting. This
  is the agreed learning setup - the user talks to me, I orchestrate Qwen2.5.

## Token-saving policy (2026-08-19)
- The biggest saver is DeepSeek context caching (already ~98% cache hits, billed ~$0.007/M).
- Use Flash by default; Pro only for a genuinely hard task, then switch back.
- Use the local Qwen2.5 model for simple/offline/private drafting (0 API tokens).
- Keep AGENTS.md concise (it is carried in every session).
- Do NOT add more MCP servers than Playwright + GitHub (each adds context overhead).
- Prefer longer sessions over frequent restarts (caching keeps them cheap).
- Goal: capable + cost-efficient; avoid over-adding tools or using Pro/cloud for trivial tasks.

## User context (for future sessions)
- The user is **not a programmer**; wants the tool safe/reversible for normal users.
- **Language preference (2026-08-21): keep Chinese (zh-Hant-HK) in the Windows language list (for talking with the assistant in Chinese and future Chinese voice/input), BUT keep all development and the app output in English only.** Do NOT switch the PC display language; do NOT localize the app. If the user messages in Chinese, reply in Chinese; keep code/docs/UI English.
- Dev PC (this one) can run the tool safely with recommended defaults; for a dev
  machine, prefer to skip "disable Script Host/macros" and "account lockout".
- The user likes the read-image skill (OCR) and the AGENTS.md memory mechanism.
- The user may test cross-session memory; recap status from this file if asked.
- To run on other PCs: copy the whole folder / extract the ZIP, turn off Smart
  App Control on Win11 if a built exe is blocked (the .ps1 launcher works either way).

## Model guidance (Flash vs Pro)
- Default is **DeepSeek V4 Flash** (fast, cheap) — the right choice for this project's
  routine work. Keep it unless a task is genuinely hard.
- WHEN I HIT A DIFFICULT PROBLEM: proactively ask the user to switch to **V4 Pro**
  for that one task (signs: repeated failures, deep reasoning/architecture, high-stakes,
  or Flash output is unsatisfactory). The user switches in the opencode UI.
- ONCE THE PROBLEM IS SOLVED: tell the user to switch BACK to **Flash** so work can
  continue fast and cheap. This is the agreed workflow: Flash by default, Pro only for
  the specific hard task, then back to Flash.
- The user is non-technical about models — give the switch instruction clearly
  (e.g., "please switch to V4 Pro now" / "please switch back to Flash").

## GUI automation (assessed 2026-08-18)
- I CANNOT click/drag native GUI apps like Power BI Desktop "like a human". No LLM
  today does this reliably for complex native canvases (vision is sampled, not
  continuous; drag/drop + fine canvas edits are brittle).
- I CAN: launch apps, open files/folders/URLs, prepare data, write DAX/M, and read
  on-screen text via the `read-image` OCR skill.
- UI-TARS (open-source GUI agent) could add real clicking via MCP, but it is still
  brittle on complex canvases and needs GPU/hardware. Consider only for simple,
  repetitive GUI tasks. (Not set up yet.)

## Recommended skills & MCP (for better dev workflow)
- Skills: `read-image` (OCR) is set up. Consider a `project-memory` skill later if
  AGENTS.md becomes too large (prefer AGENTS.md while it stays short).
- MCP servers (INSTALLED 2026-08-18):
  - **Playwright MCP** — `npx -y @playwright/mcp` (browser control + screenshots).
    Downloads Chromium on first use. Works via opencode.json global config.
  - **GitHub MCP** — official `github-mcp-server` binary at
    `~/.config/opencode/mcp/github-mcp-server/github-mcp-server.exe`, token via
    `GITHUB_PERSONAL_ACCESS_TOKEN` env var (set in registry with setx).
  - Both are defined in `~/.config/opencode/opencode.json`.
- Consider later (not installed): Memory MCP, SQLite MCP.
- Start minimal: Playwright + GitHub are the highest value. More MCP = more setup/
  complexity, so add only what's needed.
