# Project memory: System Optimizer (v1.3)

Auto-loaded by opencode every session. Keep this brief and up to date.

## What this is
A Windows GUI tool (PowerShell + WinForms) that lets a normal user safely tune
performance and harden security, with everything reversible.

## Status
- Current version: **v1.3.0** (published on GitHub + a v1.3.0 Release).
- Refactored into modular `lib/`; fixed a JSON-backup bug, a startup-cleanup
  loop bug, and the MSI build. 9/9 Pester tests pass, PSScriptAnalyzer 0 errors.
- This folder is both the source and the build output (exe + msi + lib here).
- GitHub repo: `github.com/gilbertli2025/System-Optimizer` (commit e0f0288).

## Structure
- `SystemOptimizer-GUI.ps1` = UI shell; it dot-sources `lib/*.ps1`:
  `Common.ps1` (paths, logging, JSON/CSV), `ServiceCatalog.ps1` (services),
  `SecurityItems.ps1` (10 hardening items), `MaintenanceItems.ps1` (13 items),
  `Repair.ps1` (sfc/dism/chkdsk), `Review.ps1` (security report).
- `tests/Lib.Tests.ps1` (Pester). Run: `Invoke-Pester ./tests`.
- `build.ps1` = full build (exes + MSIs + sign). `source\build-msi.ps1` = MSIs only.
- Sign cert thumbprint: `C2DD93EC094DEAD52F7C275007B646452A9D79A6`.
- 4 tabs: Performance & Services, Security & Hardening, Maintenance & Cleanup,
  System Repair. `1-Click-System-Optimizer.cmd` runs `SystemOptimizer-GUI.ps1`
  via `powershell -Bypass` (bypasses Smart App Control).

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

## v1.5 (in progress 2026-08-20)
- [x] Scheduled auto-maintenance (weekly Task Scheduler: temp cleanup, DNS, SSD trim, quick scan).
- [x] Backup improvements: BitLocker recovery key included, Verify backup, auto-detect USB backup folder.
- [ ] (later) duplicate finder, force uninstaller, driver checker.
- USB is the recommended way to run + back up settings (launcher prompts if not on USB).

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
