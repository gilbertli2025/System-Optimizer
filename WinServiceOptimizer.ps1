<#
.SYNOPSIS
  Windows Services Optimizer - a portable utility that safely disables
  non-critical Windows services to speed up a PC, restores them, and
  verifies the result. Runs on any Windows 10/11 PC (requires .NET 4.7.2+,
  included by default). No installation needed.

.DESCRIPTION
  - Optimize:  disables a curated SAFE list (telemetry, Xbox, Fax, Remote
                Registry, Error Reporting, Phone, Maps, Geolocation, etc.).
  - Optional:  additionally disables services that can affect a feature
                (Search indexing, Print Spooler, Bluetooth, Remote Desktop...).
  - Restore:   reverts every change to its previous state from the backup.
  - Verify:    confirms each targeted service is disabled and that no
                protected/critical service was changed.
  Every change is backed up to %ProgramData%\WinServiceOpt.

.EXAMPLE
  Windows-Services-Optimizer.exe                # interactive menu
  Windows-Services-Optimizer.exe -Optimize      # safe list only
  Windows-Services-Optimizer.exe -Optimize -IncludeOptional
  Windows-Services-Optimizer.exe -Restore
  Windows-Services-Optimizer.exe -Verify
  Windows-Services-Optimizer.exe -List
#>
[CmdletBinding()]
param(
    [switch]$Optimize,
    [switch]$Restore,
    [switch]$Verify,
    [switch]$IncludeOptional,
    [switch]$List
)

$ErrorActionPreference = 'Continue'
$backupDir    = "$env:ProgramData\WinServiceOpt"
$backupFile   = Join-Path $backupDir "services-backup.csv"
$snapshotFile = Join-Path $backupDir "all-services-snapshot.csv"
$logFile      = Join-Path $backupDir "optimize.log"

# Services NEVER touched, even if they match a list (system-critical / security)
$protected = @(
    'BDESVC','WinDefend','SecurityHealthService','W32Time','BITS','wuauserv',
    'TrustedInstaller','FontCache','winmgmt','eventlog','Schedule','RpcSs',
    'DcomLaunch','RpcEptMapper','LSM','SENS','CryptSvc','Dnscache','Dhcp',
    'NlaSvc','Audiosrv','AudioEndpointBuilder','gpsvc','ProfSvc','Themes'
)

# Curated SAFE list - disabling does not break normal desktop use
$safeServices = @(
    'DiagTrack',            # Connected User Experiences and Telemetry
    'dmwappushservice',     # Device Management WAP Push Message
    'WMPNetworkSvc',        # Windows Media Player Network Sharing
    'Fax',                  # Fax service
    'RetailDemo',           # Retail Demo Service
    'RemoteRegistry',       # Remote Registry (also a security improvement)
    'WerSvc',               # Windows Error Reporting
    'NetTcpPortSharing',    # Net.Tcp Port Sharing
    'PhoneSvc',             # Phone Service
    'TabletInputService',   # Touch Keyboard and Handwriting Panel
    'XblAuthManager',       # Xbox Live Auth Manager
    'XblGameSave',          # Xbox Live Game Save
    'XboxNetApiSvc',        # Xbox Live Networking
    'XboxGipSvc',           # Xbox Accessory Management
    'HoloSvc',              # Windows Mixed Reality
    'MapsBroker',           # Downloaded Maps Manager
    'lfsvc',                # Geolocation Service
    'PcaSvc'                # Program Compatibility Assistant
)

# OPTIONAL list - only with -IncludeOptional. Each may affect a feature you use.
$optionalServices = @(
    'WSearch',              # Windows Search indexing (slower file search)
    'SysMain',              # Superfetch (usually fine to disable on SSD)
    'Spooler',              # Print Spooler (disable only if you never print)
    'TermService',          # Remote Desktop Services (disable only if unused)
    'SessionEnv',           # Remote Desktop Configuration
    'UmRdpService',         # Remote Desktop UserMode Port Redirector
    'WwanSvc',              # WWAN AutoConfig (cellular adapters)
    'bthserv',              # Bluetooth Support Service
    'BTAGService',          # Bluetooth Audio Gateway
    'BthAvctpSvc',          # Bluetooth AVCTP
    'WbioSrvc',             # Windows Biometric Service (fingerprint/camera logon)
    'stisvc',               # Windows Image Acquisition (scanners/cameras)
    'SharedAccess',         # Internet Connection Sharing
    'WpcMonSvc',            # Parental Controls
    'wlidsvc',              # Microsoft Account Sign-in Assistant
    'NvTelemetryContainer', # NVIDIA Telemetry
    'WdiServiceHost',       # Diagnostic Service Host
    'WdiSystemHost'         # Diagnostic System Host
)

function Write-Log {
    param([string]$msg)
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    try { Add-Content -Path $logFile -Value $line -ErrorAction Stop } catch { }
    Write-Host $line
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-CurrentStartType {
    param([string]$name)
    try { return (Get-Service -Name $name -ErrorAction Stop).StartType } catch { return $null }
}

function Backup-State {
    if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
    $all = Get-CimInstance Win32_Service | Select-Object Name, StartMode, State
    $all | Export-Csv -Path $snapshotFile -NoTypeInformation
    if (-not (Test-Path $backupFile)) {
        @() | Export-Csv -Path $backupFile -NoTypeInformation
    }
}

function Save-BackupEntry {
    param([string]$name, [string]$oldStartType, [bool]$wasRunning)
    $row = [PSCustomObject]@{ Name=$name; OldStartType=$oldStartType; WasRunning=$wasRunning; Date=(Get-Date).ToString('o') }
    $rows = @(Import-Csv $backupFile -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne $name })
    $rows += $row
    $rows | Export-Csv -Path $backupFile -NoTypeInformation
}

function Get-RunningDependent {
    param([string]$name)
    try {
        $deps = Get-CimInstance Win32_DependentService -ErrorAction SilentlyContinue |
                Where-Object { $_.Antecedent -match "Name='$name'" }
        foreach ($d in $deps) {
            $depName = ([regex]::Match($d.Dependent, "Name='([^']+)'")).Groups[1].Value
            $dep = Get-Service -Name $depName -ErrorAction SilentlyContinue
            if ($dep -and $dep.Status -ne 'Stopped') { return $depName }
        }
    } catch { }
    return $null
}

function Disable-Services {
    param([string[]]$names)
    foreach ($name in $names) {
        if ($protected -contains $name) {
            Write-Log "SKIP (protected): $name"
            continue
        }
        if (-not (Get-Service -Name $name -ErrorAction SilentlyContinue)) {
            Write-Log "SKIP (not installed): $name"
            continue
        }
        if ((Get-CurrentStartType $name) -eq 'Disabled') {
            Write-Log "SKIP (already disabled): $name"
            continue
        }
        $dep = Get-RunningDependent $name
        if ($dep) {
            Write-Log "SKIP (running dependent '$dep'): $name"
            continue
        }
        $old = Get-CurrentStartType $name
        $wasRunning = ((Get-Service -Name $name).Status -eq 'Running')
        try {
            Set-Service -Name $name -StartupType Disabled -ErrorAction Stop
            try { Stop-Service -Name $name -Force -ErrorAction Stop } catch {
                Write-Log "WARN (could not stop): $name"
            }
            Save-BackupEntry $name $old $wasRunning
            Write-Log "DISABLED: $name (was $old)"
        } catch {
            Write-Log "ERROR disabling $name : $($_.Exception.Message)"
        }
    }
}

function Restore-Services {
    if (-not (Test-Path $backupFile)) {
        Write-Host "No backup found at $backupFile - nothing to restore."
        return
    }
    $rows = @(Import-Csv $backupFile)
    if ($rows.Count -eq 0) { Write-Host "Backup is empty - nothing to restore."; return }
    foreach ($row in $rows) {
        $name = $row.Name
        if (-not (Get-Service -Name $name -ErrorAction SilentlyContinue)) { continue }
        $old = $row.OldStartType
        try {
            Set-Service -Name $name -StartupType $old -ErrorAction Stop
            if ($row.WasRunning -eq 'True') { Start-Service -Name $name -ErrorAction SilentlyContinue }
            Write-Log "RESTORED: $name (startup -> $old)"
        } catch {
            Write-Log "ERROR restoring $name : $($_.Exception.Message)"
        }
    }
    Write-Host "Restore complete. Backup file kept at $backupFile."
}

function Show-List {
    Write-Host "`nSAFE (disabled by default):"
    $safeServices | ForEach-Object { Write-Host ("  {0,-24} {1}" -f $_, (Get-CurrentStartType $_)) }
    Write-Host "`nOPTIONAL (only with -IncludeOptional):"
    $optionalServices | ForEach-Object { Write-Host ("  {0,-24} {1}" -f $_, (Get-CurrentStartType $_)) }
    Write-Host "`nBackup/log folder: $backupDir"
}

function Invoke-Verify {
    $global:passCount = 0; $global:failCount = 0; $global:warnCount = 0
    function Report {
        param([string]$state, [string]$msg)
        switch ($state) {
            'PASS'  { $global:passCount++; Write-Host ("  [PASS]  " + $msg) -ForegroundColor Green }
            'FAIL'  { $global:failCount++; Write-Host ("  [FAIL]  " + $msg) -ForegroundColor Red }
            'WARN'  { $global:warnCount++; Write-Host ("  [WARN]  " + $msg) -ForegroundColor Yellow }
            default { Write-Host ("  [INFO]  " + $msg) -ForegroundColor Cyan }
        }
    }

    Write-Host "=== Verification Report ===" -ForegroundColor White
    Write-Host ("Date/time: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -ForegroundColor Gray

    if (-not (Test-Path $backupDir)) {
        Write-Host "No backup folder found at $backupDir." -ForegroundColor Red
        Write-Host "The optimizer has NOT been run on this PC." -ForegroundColor Yellow
        return 2
    }

    $ran = $false
    if (Test-Path $logFile) {
        $log = Get-Content $logFile -ErrorAction SilentlyContinue
        if ($log -match "Optimizer started") {
            $ran = $true
            Report PASS "Optimization run detected in log."
            if ($log -match "=== Optimization finished ===") { Report PASS "Run completed with a finish marker." }
            else { Report WARN "Run started but no finish marker found (may have been interrupted)." }
        } else {
            Report WARN "Log exists but no start marker - optimization may not have run."
        }
    } else {
        Report FAIL "Log file not found ($logFile)."
    }

    if (-not (Test-Path $backupFile)) {
        Report FAIL "Backup file not found ($backupFile)."
        Write-Host "No services were changed - nothing to verify." -ForegroundColor Yellow
        return 2
    }

    $rows = @(Import-Csv $backupFile -ErrorAction SilentlyContinue)
    if ($rows.Count -eq 0) {
        Write-Host "Backup file is empty - no services were targeted." -ForegroundColor Yellow
        return 2
    }

    Write-Host "`nServices targeted by the optimization: $($rows.Count)" -ForegroundColor White
    foreach ($row in $rows) {
        $name = $row.Name
        $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
        if (-not $svc) {
            Report WARN "$name - service no longer exists."
            continue
        }
        $type = $svc.StartType
        if ($type -eq 'Disabled') {
            Report PASS "$name - disabled (current: $type, status: $($svc.Status))."
        } else {
            Report FAIL "$name - expected Disabled but current is $type."
        }
    }

    if ($ran) {
        $errLines = $log | Where-Object { $_ -match "^ERROR" }
        if ($errLines) {
            Report FAIL "The log contains error(s):"
            $errLines | ForEach-Object { Write-Host ("       " + $_) -ForegroundColor Red }
        } else {
            Report PASS "No errors found in the optimization log."
        }
    }

    if (Test-Path $snapshotFile) {
        Write-Host "`nProtected / critical services (must be unchanged):" -ForegroundColor White
        $snap = @(Import-Csv $snapshotFile -ErrorAction SilentlyContinue)
        $checked = 0
        foreach ($row in $snap) {
            if ($protected -notcontains $row.Name) { continue }
            $cur = Get-Service -Name $row.Name -ErrorAction SilentlyContinue
            if (-not $cur) { continue }
            $checked++
            $before = $row.StartMode
            $after = $cur.StartType
            $norm = switch ($before) {
                'Auto'      { 'Automatic' }
                'AutoStart' { 'Automatic' }
                default     { $before }
            }
            if ($norm -eq $after) { Report PASS "$($row.Name) - unchanged ($before)." }
            else { Report WARN "$($row.Name) - changed from $before to $after." }
        }
        if ($checked -eq 0) { Report WARN "No protected services found in snapshot." }
    } else {
        Report WARN "Snapshot file missing - cannot verify protected services."
    }

    Write-Host ""
    Write-Host ("Summary:  PASS=$global:passCount  FAIL=$global:failCount  WARN=$global:warnCount") -ForegroundColor White
    if ($global:failCount -gt 0) {
        Write-Host "RESULT: Issues found - review the FAIL lines above." -ForegroundColor Red
        return 1
    } elseif (-not $ran) {
        Write-Host "RESULT: Backup exists but run not confirmed - re-run the optimization." -ForegroundColor Yellow
        return 1
    } else {
        Write-Host "RESULT: OK - optimization verified successfully." -ForegroundColor Green
        return 0
    }
}

function Restart-Admin {
    param([string[]]$switches)
    Write-Host "Requesting administrator privileges..."
    $me = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($me) -or -not (Test-Path $me)) {
        $me = [Diagnostics.Process]::GetCurrentProcess().Path
    }
    if ($me -like "*.ps1") {
        $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$me`" " + ($switches -join " ")
        Start-Process powershell -Verb RunAs -ArgumentList $argList
    } else {
        Start-Process -FilePath $me -ArgumentList $switches -Verb RunAs
    }
    exit
}

function Invoke-Action {
    param([string]$action)
    if ($action -eq 'Verify') { Invoke-Verify; return }
    if ($action -eq 'List')   { Show-List; return }
    if (-not (Test-Admin)) {
        $sw = @("-" + $action)
        if ($IncludeOptional -and $action -eq 'Optimize') { $sw += '-IncludeOptional' }
        Restart-Admin $sw
        return
    }
    if ($action -eq 'Optimize') {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Write-Log "=== Windows Services Optimizer started ==="
        Backup-State
        Disable-Services $safeServices
        if ($IncludeOptional) { Disable-Services $optionalServices }
        Write-Log "=== Optimization finished ==="
        Write-Host "`nDone. Backup at $backupFile. To revert, choose Restore or run with -Restore."
    } elseif ($action -eq 'Restore') {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Write-Log "=== Windows Services Optimizer started ==="
        Restore-Services
        Write-Log "=== Optimization finished ==="
    }
}

# --- Non-interactive (command-line) mode ---
if ($Optimize) { Invoke-Action 'Optimize'; exit }
if ($Restore)  { Invoke-Action 'Restore';  exit }
if ($Verify)   { Invoke-Action 'Verify';   exit }
if ($List)     { Invoke-Action 'List';     exit }

# --- Interactive menu ---
while ($true) {
    Write-Host ""
    Write-Host "=== Windows Services Optimizer ===" -ForegroundColor White
    Write-Host "   1) Optimize (safe list)"
    Write-Host "   2) Optimize + optional list"
    Write-Host "   3) Restore (undo everything)"
    Write-Host "   4) Verify (check the result)"
    Write-Host "   5) Show service lists"
    Write-Host "   Q) Quit"
    $choice = Read-Host "Choose an option"
    switch ($choice.Trim().ToUpper()) {
        '1' { $script:IncludeOptional = $false; Invoke-Action 'Optimize'; Read-Host "`nPress Enter to continue..." }
        '2' { $script:IncludeOptional = $true;  Invoke-Action 'Optimize'; Read-Host "`nPress Enter to continue..." }
        '3' { Invoke-Action 'Restore'; Read-Host "`nPress Enter to continue..." }
        '4' { Invoke-Action 'Verify';  Read-Host "`nPress Enter to continue..." }
        '5' { Invoke-Action 'List';    Read-Host "`nPress Enter to continue..." }
        'Q' { Write-Host "Bye."; exit }
        default { Write-Host "Invalid choice." }
    }
}
