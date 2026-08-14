<#
.SYNOPSIS
  System Optimizer - a single GUI that combines Performance (services) tuning
  and Security hardening. Tick what you want, apply it, and restore everything
  back to defaults with one click. Every change is backed up.

.DESCRIPTION
  Tab "Performance & Services": disable safe/optional Windows services.
  Tab "Security & Hardening": items 1-10 (Defender, firewall, scans, auto-lock,
  Edge/Chrome hardening, System Restore, BitLocker, AutoRun, account lockout,
  Office macros + Windows Script Host).
  Backups: %ProgramData%\WinServiceOpt and %ProgramData%\WinSecOpt.
  Buttons at the bottom apply / restore / verify everything at once.

.EXAMPLE
  SystemOptimizer.exe
  SystemOptimizer.exe -NoElevate -SmokeTest   # dev only
#>
[CmdletBinding()]
param(
    [switch]$SmokeTest,
    [switch]$NoElevate
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$ErrorActionPreference = 'Continue'

# ---------- folders ----------
$wsDir         = "$env:ProgramData\WinServiceOpt"
$wsBackupFile  = Join-Path $wsDir "services-backup.csv"
$wsSnapshot    = Join-Path $wsDir "all-services-snapshot.csv"

$secDir        = "$env:ProgramData\WinSecOpt"
$secBackupFile = Join-Path $secDir "backup.json"
$secReviewFile = Join-Path $secDir "security-review.txt"

$maintBackupFile = Join-Path (Join-Path $env:ProgramData "SystemOptimizer") "maintenance-backup.json"

$logFile       = Join-Path (Join-Path $env:ProgramData "SystemOptimizer") "unified.log"

# ---------- data ----------
$protected = @(
    'BDESVC','WinDefend','SecurityHealthService','W32Time','BITS','wuauserv',
    'TrustedInstaller','FontCache','winmgmt','eventlog','Schedule','RpcSs',
    'DcomLaunch','RpcEptMapper','LSM','SENS','CryptSvc','Dnscache','Dhcp',
    'NlaSvc','Audiosrv','AudioEndpointBuilder','gpsvc','ProfSvc','Themes'
)

$safeServices = @(
    'DiagTrack','dmwappushservice','WMPNetworkSvc','Fax','RetailDemo',
    'RemoteRegistry','WerSvc','NetTcpPortSharing','PhoneSvc','TabletInputService',
    'XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc','HoloSvc',
    'MapsBroker','lfsvc','PcaSvc'
)

$optionalServices = @(
    'WSearch','SysMain','Spooler','TermService','SessionEnv','UmRdpService',
    'WwanSvc','bthserv','BTAGService','BthAvctpSvc','WbioSrvc','stisvc',
    'SharedAccess','WpcMonSvc','wlidsvc','NvTelemetryContainer',
    'WdiServiceHost','WdiSystemHost'
)

$edgePolicies   = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
$chromePolicies = 'HKLM:\SOFTWARE\Policies\Google\Chrome'

$secItems = @(
    @{ id='cloud';     text='1.  Defender cloud protection (block at first sight)' },
    @{ id='firewall';  text='2.  Firewall: block all unsolicited inbound by default' },
    @{ id='scan';      text='3.  Daily Defender quick scan at 03:00' },
    @{ id='lock';      text='4.  Auto-lock the screen after 10 min idle' },
    @{ id='browsers';  text='5.  Harden Edge + Chrome browsers' },
    @{ id='restore';   text='6.  Enable System Restore + weekly restore points' },
    @{ id='bitlocker'; text='7.  BitLocker on C: (TPM) - protect against theft' },
    @{ id='autorun';   text='8.  Disable AutoRun on removable drives' },
    @{ id='lockout';   text='9.  Account lockout (5 tries / 15 min)' },
    @{ id='officewsh'; text='10. Block Office macros from internet + disable Script Host' }
)

$maintItems = @(
    @{ id='cleantemp';    text='1.  Clear temporary files (user + Windows temp)' },
    @{ id='wucleanup';    text='2.  Windows Update cleanup (StartComponentCleanup)' },
    @{ id='trimssd';      text='3.  Re-trim SSD (Optimize-Volume C:)' },
    @{ id='flushdns';     text='4.  Flush DNS cache' },
    @{ id='gamedvr';      text='5.  Disable Game DVR background recording' },
    @{ id='storagesense'; text='6.  Enable Storage Sense (auto temp + recycle-bin cleanup)' },
    @{ id='recyclebin';   text='7.  Empty Recycle Bin' },
    @{ id='browscache';   text='8.  Clear Edge + Chrome browser cache' },
    @{ id='startupapps';  text='9.  Disable third-party startup apps (current user)' },
    @{ id='vfxperf';      text='10. Visual effects -> best performance' },
    @{ id='faststartup';  text='11. Enable Fast Startup (faster boot)' },
    @{ id='tips';         text='12. Disable Windows tips & suggestions' },
    @{ id='powerplan';    text='13. Power plan -> High performance (battery drains faster)' }
)

$helpText = @"
System Optimizer - User Guide
=============================

This tool has two tabs plus master buttons. Everything you enable can be
reverted with "Restore ALL to defaults". Every change is logged and backed up.

------------------------------------------------------------------
TAB 1 - PERFORMANCE & SERVICES
------------------------------------------------------------------
Windows runs many background services you may not need. Disabling them
frees CPU, memory and disk activity. Two lists are provided:

  SAFE services (recommended, pre-checked)
    Safe to stop for normal desktop use. Includes telemetry (DiagTrack),
    Xbox services, Fax, Remote Registry, Error Reporting, Phone, Maps,
    Geolocation, Program Compatibility Assistant, Mixed Reality, etc.
    Disabling these does not break everyday work.

  OPTIONAL services (tick only if you do not use the feature)
    Each one affects a feature you might use:
      - WSearch: Windows Search indexing (slower file search if off)
      - SysMain: Superfetch (fine to disable on SSD)
      - Spooler: printing (disable only if you never print)
      - TermService/SessionEnv/UmRdpService: Remote Desktop
      - WwanSvc: cellular/4G adapters
      - bthserv/BTAGService/BthAvctpSvc: Bluetooth
      - WbioSrvc: fingerprint/camera logon
      - stisvc: scanners and cameras
      - SharedAccess: Internet Connection Sharing
      - WpcMonSvc: parental controls
      - wlidsvc: Microsoft account sign-in
      - NvTelemetryContainer: NVIDIA telemetry
      - WdiServiceHost/WdiSystemHost: diagnostics

  Buttons:
    Disable services (selected) : disable the services you ticked (backed up first).
    Restore services  : set them all back to their original startup type.
    Restore optional only : re-enable ONLY the OPTIONAL services you disabled
             (print, Remote Desktop, Bluetooth, etc.) - handy if you
             over-selected and a feature stopped working. Your safe-service
             tweaks stay untouched.
    Verify services   : confirm each backed-up service is actually disabled.

  TIP: the OPTIONAL list can disable printing, Remote Desktop, Bluetooth,
  search or scanners. If a feature stops working, use "Restore optional only".

  Note: system-critical and security services are always protected and are
  never touched, even if they appear on a list.

------------------------------------------------------------------
TAB 2 - SECURITY & HARDENING
------------------------------------------------------------------
Tick the hardening items you want, then "Apply selected".

  1. Defender cloud protection (block at first sight)
     Enables Microsoft's cloud-delivered protection: MAPS=2 (advanced),
     send safe samples, and block level 2. Lets Defender stop new malware
     quickly using cloud reputation.
     Tradeoff: sends limited malware/URL info to Microsoft.

  2. Firewall: block all unsolicited inbound by default
     Sets the Windows Firewall default inbound action to Block for the
     Domain, Private and Public profiles. Outbound and established
     connections still work.
     Effect: unsolicited incoming connections are dropped, which improves
     security. If you use file/print sharing to other devices or remote
     management, you may need to add allow rules.

  3. Daily Defender quick scan at 03:00
     Schedules a daily quick scan of the most common infection points.

  4. Auto-lock screen after 10 minutes idle
     Locks your PC automatically after 10 minutes of inactivity, requiring
     your password/PIN to get back in.

  5. Harden Edge + Chrome browsers
     Applies policy registry settings to both browsers:
       - Edge: SmartScreen + SmartScreen for downloads on, block dangerous
               downloads, block third-party cookies, block popups, strict
               site isolation, block WebUSB/WebSerial, no credit-card autofill.
       - Chrome: Enhanced Safe Browsing, block dangerous downloads, block
               third-party cookies, block popups, strict site isolation,
               block WebUSB/WebSerial, no credit-card autofill.
     Note: blocking third-party cookies may break some sites that rely on
     them for login. Browsers show "Managed by your organization" while
     these policies are active - this is expected.

  6. Enable System Restore + weekly restore points
     Turns on System Protection for your fixed drives, allows more than one
     restore point per day, creates a restore point now, and schedules a
     weekly restore point (Sunday 04:00).
     Restore points undo bad system changes (drivers, updates, registry).
     IMPORTANT: restore points are NOT a backup of your personal files.

  7. BitLocker on C: (TPM)
     Encrypts the system drive so data is unreadable if the PC is stolen.
     Requires Windows Pro/Enterprise and a TPM. Encryption runs in the
     background; the PC is still usable.
     Restore does NOT decrypt the drive (for safety); decrypt manually with
     the recovery key if you want it off.

  8. Disable AutoRun on removable drives
     Sets NoDriveTypeAutoRun so USB sticks and other removable drives can
     never auto-start software. Stops a common malware delivery method.

  9. Account lockout (5 tries / 15 min)
     After 5 failed sign-in attempts the account is locked for 15 minutes.
     Slows down password-guessing attacks against this PC.

 10. Block Office macros from the internet + disable Windows Script Host
     Stops Word/Excel/PowerPoint/Outlook from running macros inside files
     downloaded from the internet, and disables VBS/JS scripts (Windows
     Script Host). Two very common malware entry points.
     Tradeoff: legitimately scripted or macro-enabled files may be blocked.

  Buttons:
    Apply security (selected) : apply the ticked hardening items (backed up first).
    Restore security  : revert ALL applied hardening to original settings.
    Restore checked   : revert ONLY the hardening items you currently have
             ticked. Handy if one setting (e.g. browser hardening or the
             firewall) caused a problem and you want to undo just that.
     Security review   : print a snapshot report of this PC's security state.

------------------------------------------------------------------
TAB 3 - MAINTENANCE & CLEANUP
------------------------------------------------------------------
Items 1-6 are safe and recommended; 7-10 are optional and off by default.
  1. Clear temporary files       - frees space (user + Windows temp).
  2. Windows Update cleanup      - removes old superseded update files
                                   (Dism StartComponentCleanup; can be slow).
  3. Re-trim SSD                 - keeps an SSD fast (C:).
  4. Flush DNS cache             - clears stale DNS lookups.
  5. Disable Game DVR            - stops background game recording (frees RAM).
  6. Enable Storage Sense        - Windows auto-cleans temp + recycle bin.
           OFF by default: Windows may also auto-delete older System Restore
           points and Downloads as part of its cleanup. Turn this ON only if
           you are OK with that.
  7. Empty Recycle Bin           - frees space but permanently deletes files.
  8. Clear Edge + Chrome cache   - frees space; first page loads slower.
  9. Disable third-party startup apps (current user) - faster boot; reversible.
  10. Visual effects -> best performance - minor on new PCs, helps older ones.
  11. Enable Fast Startup - faster boot (note: on laptops, shut down uses hybrid).
  12. Disable Windows tips & suggestions - fewer notifications; reversible.
  13. Power plan -> High performance - faster, but battery drains faster on laptops.

  Buttons:
    Run selected cleanup : run the ticked items.
    Restore settings     : revert the reversible items (5,6,9,10).
    Cleanup report       : show current maintenance state.

------------------------------------------------------------------
TAB 4 - SYSTEM REPAIR
------------------------------------------------------------------
Repair damaged Windows files or the disk. These can take a long time,
so they are NOT part of "Apply ALL" - run them here only when needed.
  sfc /scannow           : verifies and repairs system files (5-10 min).
  DISM /restorehealth    : repairs the Windows image (10-20+ min, needs net).
  chkdsk C: /f           : checks the disk for errors - REQUIRES A RESTART.

------------------------------------------------------------------
MASTER BUTTONS (bottom)
------------------------------------------------------------------
  Apply ALL selected       : applies ticked services, security AND cleanup.
  Restore ALL to defaults  : reverts everything to its original state.
  Full review / verify     : runs the services verify + security + cleanup check.
  Help                     : this help.

  Restore intentionally does NOT undo two things (for safety):
    - BitLocker: the drive stays encrypted.
    - System Restore protection: stays enabled so you keep your safety net.
  Cleanup actions (1-4, 7-8) free space and are not reverted by Restore.

------------------------------------------------------------------
WHERE THINGS ARE STORED
------------------------------------------------------------------
  Services backup      : %ProgramData%\WinServiceOpt\services-backup.csv
  Security backup      : %ProgramData%\WinSecOpt\backup.json
  Unified log          : %ProgramData%\SystemOptimizer\unified.log
  Weekly restore point task: WeeklySystemRestorePoint (Sun 04:00)

------------------------------------------------------------------
SECURITY BEST PRACTICES (beyond this tool)
------------------------------------------------------------------
This tool keeps the system healthy. These habits protect you further:
  1. Accounts: use a Standard (non-admin) account for daily work and keep
     admin for installs only. Turn on Windows Hello (PIN / biometrics) and
     two-factor authentication on your Microsoft account and email.
  2. Passwords: use a password manager so you never reuse passwords.
  3. Software: download only from official sites. NEVER use cracked software
     or keygens - the #1 source of infection.
  4. Email/web: be careful clicking links or attachments, even from people
     you know. Keep your browser and Windows updated.
  5. Backups: restore points are NOT backups. Turn on File History for your
     documents and keep an offline copy (USB/cloud) of important files.
  6. Network: be careful on public Wi-Fi (use a VPN for sensitive work) and
     lock the screen when you step away.
  7. Updates: let Windows update automatically, reboot to apply, and restart
     weekly.

------------------------------------------------------------------
NOTES FOR A FRESH WINDOWS 11 PC
------------------------------------------------------------------
  - Smart App Control (Win11) can block this self-signed tool. If the exe
    is blocked, turn it off: Windows Security > App & browser control >
    Smart App Control > Off, then reboot. (It cannot be re-enabled without
    resetting Windows.)
  - The 1-Click script installs WSO-Trust.cer so the signed exe is trusted.
  - Reboot after applying for the full effect.
"@

# ---------- helpers ----------
$script:logBox = $null
$script:svcChecks = [System.Collections.ArrayList]@()
$script:secChecks = [System.Collections.ArrayList]@()
$script:maintChecks = [System.Collections.ArrayList]@()
$script:repairChecks = [System.Collections.ArrayList]@()

function Write-Log {
    param([string]$msg)
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    New-Item -ItemType Directory -Path (Split-Path $logFile) -Force | Out-Null
    try { Add-Content -Path $logFile -Value $line -ErrorAction Stop } catch { }
    if ($script:logBox) {
        $script:logBox.AppendText($line + "`r`n")
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin) -and -not $NoElevate) {
    [void][System.Windows.Forms.MessageBox]::Show(
        "System Optimizer needs administrator rights.`n`nClick OK to restart with elevation.",
        "Admin required", 'OK', 'Information')
    $me = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($me) -or -not (Test-Path $me)) { $me = [Diagnostics.Process]::GetCurrentProcess().Path }
    Start-Process -FilePath $me -Verb RunAs
    exit
}

# ================= SERVICES =================
function Get-CurrentStartType {
    param([string]$name)
    try { return (Get-Service -Name $name -ErrorAction Stop).StartType } catch { return '' }
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

function Backup-Services {
    New-Item -ItemType Directory -Path $wsDir -Force | Out-Null
    Get-CimInstance Win32_Service | Select-Object Name, StartMode, State | Export-Csv -Path $wsSnapshot -NoTypeInformation
    if (-not (Test-Path $wsBackupFile)) { @() | Export-Csv -Path $wsBackupFile -NoTypeInformation }
}

function Save-SvcBackupEntry {
    param([string]$name, [string]$oldStartType, [bool]$wasRunning, [string]$category)
    $row = [PSCustomObject]@{ Name=$name; OldStartType=$oldStartType; WasRunning=$wasRunning; Category=$category; Date=(Get-Date).ToString('o') }
    $rows = @(Import-Csv $wsBackupFile -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne $name })
    $rows += $row
    $rows | Export-Csv -Path $wsBackupFile -NoTypeInformation
}

function Get-ServiceCategory {
    param([string]$name)
    if ($optionalServices -contains $name) { return 'Optional' }
    if ($safeServices -contains $name) { return 'Safe' }
    return 'Unknown'
}

function Disable-Services {
    param([string[]]$names)
    foreach ($name in $names) {
        if ($protected -contains $name) { Write-Log "SKIP (protected): $name"; continue }
        if (-not (Get-Service -Name $name -ErrorAction SilentlyContinue)) { Write-Log "SKIP (not installed): $name"; continue }
        if ((Get-CurrentStartType $name) -eq 'Disabled') { Write-Log "SKIP (already disabled): $name"; continue }
        $dep = Get-RunningDependent $name
        if ($dep) { Write-Log "SKIP (running dependent '$dep'): $name"; continue }
        $old = Get-CurrentStartType $name
        $wasRunning = ((Get-Service -Name $name).Status -eq 'Running')
        try {
            Set-Service -Name $name -StartupType Disabled -ErrorAction Stop
            try { Stop-Service -Name $name -Force -ErrorAction Stop } catch { Write-Log "WARN (could not stop): $name" }
            Save-SvcBackupEntry $name $old $wasRunning (Get-ServiceCategory $name)
            Write-Log "DISABLED: $name (was $old)"
        } catch { Write-Log "ERROR disabling $name : $($_.Exception.Message)" }
    }
}

function Restore-OptionalServices {
    if (-not (Test-Path $wsBackupFile)) { Write-Log "No services backup - nothing to restore."; return }
    $rows = @(Import-Csv $wsBackupFile | Where-Object { $_.Category -eq 'Optional' })
    if ($rows.Count -eq 0) { Write-Log "No OPTIONAL services in the backup to restore. (Optional services restore print, Remote Desktop, Bluetooth, etc.)"; return }
    $restored = 0
    foreach ($row in $rows) {
        $name = $row.Name
        if (-not (Get-Service -Name $name -ErrorAction SilentlyContinue)) { continue }
        try {
            Set-Service -Name $name -StartupType $row.OldStartType -ErrorAction Stop
            if ($row.WasRunning -eq 'True') { Start-Service -Name $name -ErrorAction SilentlyContinue }
            Write-Log "RESTORED: $name (optional -> $($row.OldStartType))"
            $restored++
        } catch { Write-Log "ERROR restoring $name : $($_.Exception.Message)" }
    }
    if ($restored -eq 0) { Write-Log "No optional services were changed (all already restored)." }
}

function Restore-Services {
    if (-not (Test-Path $wsBackupFile)) { Write-Log "No services backup - nothing to restore."; return }
    $rows = @(Import-Csv $wsBackupFile)
    if ($rows.Count -eq 0) { Write-Log "Services backup empty - nothing to restore."; return }
    foreach ($row in $rows) {
        $name = $row.Name
        if (-not (Get-Service -Name $name -ErrorAction SilentlyContinue)) { continue }
        try {
            Set-Service -Name $name -StartupType $row.OldStartType -ErrorAction Stop
            if ($row.WasRunning -eq 'True') { Start-Service -Name $name -ErrorAction SilentlyContinue }
            Write-Log "RESTORED: $name (startup -> $($row.OldStartType))"
        } catch { Write-Log "ERROR restoring $name : $($_.Exception.Message)" }
    }
}

function Verify-Services {
    $p = 0; $f = 0; $w = 0
    if (-not (Test-Path $wsDir)) { Write-Log "[FAIL] no services backup folder - optimizer not run."; return }
    if (-not (Test-Path $wsBackupFile)) { Write-Log "[FAIL] services backup file missing."; return }
    $rows = @(Import-Csv $wsBackupFile -ErrorAction SilentlyContinue)
    if ($rows.Count -eq 0) { Write-Log "Services backup empty - nothing to verify."; return }
    Write-Log "Services targeted: $($rows.Count)"
    foreach ($row in $rows) {
        $svc = Get-Service -Name $row.Name -ErrorAction SilentlyContinue
        if (-not $svc) { Write-Log "[WARN] $($row.Name) no longer exists."; $w++; continue }
        if ($svc.StartType -eq 'Disabled') { Write-Log "[PASS] $($row.Name) disabled."; $p++ }
        else { Write-Log "[FAIL] $($row.Name) expected Disabled, is $($svc.StartType)."; $f++ }
    }
    Write-Log "Services: PASS=$p FAIL=$f WARN=$w"
}

# ================= SECURITY helpers =================
function Get-Backup {
    if (Test-Path $secBackupFile) { try { return @(Get-Content $secBackupFile -Raw | ConvertFrom-Json) } catch { return @() } }
    return @()
}

function Save-BackupEntry {
    param([string]$name, [string]$value)
    $rows = @(Get-Backup | Where-Object { $_.Name -ne $name })
    $rows += [PSCustomObject]@{ Name = $name; Value = $value }
    New-Item -ItemType Directory -Path $secDir -Force | Out-Null
    $rows | ConvertTo-Json | Set-Content -Path $secBackupFile -Encoding UTF8
}

function Get-MpSetting { try { return (Get-MpPreference -ErrorAction Stop) } catch { return $null } }

# --- item functions ---
function Apply-CloudProtection {
    $mp = Get-MpSetting
    if (-not $mp) { Write-Log "SKIP cloud protection: Defender preferences unavailable."; return }
    if ($mp.MAPS -eq 2 -and $mp.SubmitSamplesConsent -eq 1 -and $mp.CloudBlockLevel -eq 2) { Write-Log "SKIP cloud protection: already hardened."; return }
    Save-BackupEntry 'cloud' (@{ MAPS=$mp.MAPS; SubmitSamplesConsent=$mp.SubmitSamplesConsent; CloudBlockLevel=$mp.CloudBlockLevel } | ConvertTo-Json -Compress)
    Set-MpPreference -MAPS 2 -SubmitSamplesConsent 1 -CloudBlockLevel 2 -ErrorAction Stop
    Write-Log "ENABLED: Defender cloud protection."
}

function Apply-FirewallBlock {
    $changed = $false
    foreach ($profile in @('Domain','Private','Public')) {
        $f = Get-NetFirewallProfile -Name $profile
        if ($f.DefaultInboundAction -eq 'Block' -and $f.Enabled -eq $true) { continue }
        if (-not $changed) {
            $old = @{}
            foreach ($p in @('Domain','Private','Public')) {
                $pf = Get-NetFirewallProfile -Name $p
                $old[$p] = @{ DefaultInboundAction="$($pf.DefaultInboundAction)"; Enabled=$pf.Enabled }
            }
            Save-BackupEntry 'firewall' ($old | ConvertTo-Json -Compress)
            $changed = $true
        }
        Set-NetFirewallProfile -Name $profile -DefaultInboundAction Block -Enabled True -ErrorAction Stop
    }
    if ($changed) { Write-Log "ENABLED: firewall blocks all inbound by default." } else { Write-Log "SKIP firewall: already Block + enabled." }
}

function Apply-ScanSchedule {
    $mp = Get-MpSetting
    if (-not $mp) { Write-Log "SKIP scan schedule: Defender preferences unavailable."; return }
    if ($mp.ScanScheduleQuickScanTime -eq 3) { Write-Log "SKIP scan schedule: already 03:00."; return }
    Save-BackupEntry 'scan' ("$($mp.ScanScheduleQuickScanTime)")
    Set-MpPreference -ScanScheduleQuickScanTime 3 -ErrorAction Stop
    Write-Log "ENABLED: daily quick scan at 03:00."
}

function Apply-AutoLock {
    $d = 'HKCU:\Control Panel\Desktop'
    $oldActive = (Get-ItemProperty $d -Name ScreenSaveActive -ErrorAction SilentlyContinue).ScreenSaveActive
    $oldSecure = (Get-ItemProperty $d -Name ScreenSaverIsSecure -ErrorAction SilentlyContinue).ScreenSaverIsSecure
    $oldTimeout = (Get-ItemProperty $d -Name ScreenSaveTimeOut -ErrorAction SilentlyContinue).ScreenSaveTimeOut
    if ($oldSecure -eq '1') { Write-Log "SKIP auto-lock: already locks after idle."; return }
    Save-BackupEntry 'lock' (@{ Active="$oldActive"; Secure="$oldSecure"; Timeout="$oldTimeout" } | ConvertTo-Json -Compress)
    Set-ItemProperty $d -Name ScreenSaveActive -Value '1'
    Set-ItemProperty $d -Name ScreenSaverIsSecure -Value '1'
    Set-ItemProperty $d -Name ScreenSaveTimeOut -Value '600'
    Write-Log "ENABLED: auto-lock after 10 min idle."
}

function Apply-BrowserHardening {
    $edge = @{
        'SmartScreenEnabled'=1; 'SmartScreenForTrustedDownloadsEnabled'=1; 'SafeBrowsingEnabled'=1;
        'DownloadRestrictions'=2; 'BlockThirdPartyCookies'=1; 'DefaultPopupsSetting'=2; 'SitePerProcess'=1;
        'DefaultWebUsbSetting'=2; 'DefaultWebSerialSetting'=2; 'AutofillCreditCardEnabled'=0
    }
    $chrome = @{
        'SafeBrowsingProtectionLevel'=2; 'DownloadRestrictions'=2; 'BlockThirdPartyCookies'=1;
        'DefaultPopupsSetting'=2; 'SitePerProcess'=1; 'DefaultWebUsbSetting'=2; 'DefaultWebSerialSetting'=2;
        'AutofillCreditCardEnabled'=0
    }
    $already = ((Get-ItemProperty $edgePolicies -Name DownloadRestrictions -ErrorAction SilentlyContinue).DownloadRestrictions -eq 2) -and
               ((Get-ItemProperty $chromePolicies -Name DownloadRestrictions -ErrorAction SilentlyContinue).DownloadRestrictions -eq 2)
    if ($already) { Write-Log "SKIP browsers: already hardened."; return }
    $old = @{ edge=@{}; chrome=@{} }
    foreach ($b in @('edge','chrome')) {
        $key = if ($b -eq 'edge') { $edgePolicies } else { $chromePolicies }
        $pol = if ($b -eq 'edge') { $edge } else { $chrome }
        foreach ($pn in $pol.Keys) { $cur = (Get-ItemProperty $key -Name $pn -ErrorAction SilentlyContinue).$pn; $old[$b][$pn] = $(if ($null -eq $cur) { 'MISSING' } else { $cur }) }
    }
    Save-BackupEntry 'browsers' ($old | ConvertTo-Json -Compress)
    foreach ($b in @('edge','chrome')) {
        $key = if ($b -eq 'edge') { $edgePolicies } else { $chromePolicies }
        $pol = if ($b -eq 'edge') { $edge } else { $chrome }
        New-Item -ItemType Directory -Path $key -Force | Out-Null
        foreach ($pn in $pol.Keys) { Set-ItemProperty -Path $key -Name $pn -Value $pol[$pn] -Type DWord -ErrorAction Stop }
    }
    Write-Log "ENABLED: browser hardening for Edge + Chrome."
}

function Apply-SystemRestore {
    $drives = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object { $_.DeviceID })
    if ($drives.Count -eq 0) { Write-Log "SKIP restore points: no fixed drive found."; return }
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $freqNow = (Get-ItemProperty $key -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
    Save-BackupEntry 'restore' (@{ Drives=($drives -join ','); Frequency="$freqNow" } | ConvertTo-Json -Compress)
    foreach ($d in $drives) { try { Enable-ComputerRestore -Drive "$d\" -ErrorAction Stop; Write-Log "ENABLED: system protection on $d." } catch { Write-Log "WARN enable protection $d`: $($_.Exception.Message)" } }
    try { Set-ItemProperty $key -Name SystemRestorePointCreationFrequency -Value 0 -Type DWord -ErrorAction Stop } catch { Write-Log "WARN set restore frequency: $($_.Exception.Message)" }
    $taskName = 'WeeklySystemRestorePoint'
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -Command "Checkpoint-Computer -Description ''Weekly Restore Point'' -RestorePointType MODIFY_SETTINGS"'
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 4am
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    try { Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force -ErrorAction Stop | Out-Null; Write-Log "ENABLED: weekly restore point task every Sunday 04:00." } catch { Write-Log "WARN schedule weekly task: $($_.Exception.Message)" }
    try { Checkpoint-Computer -Description 'System Optimizer baseline' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop | Out-Null; Write-Log "Created a restore point now." } catch { Write-Log "WARN checkpoint now: $($_.Exception.Message)" }
}

function Apply-BitLocker {
    $bl = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction SilentlyContinue
    if ($bl -and $bl.ProtectionStatus -eq 'On') { Save-BackupEntry 'bitlocker' '{"State":"AlreadyOn"}'; Write-Log "SKIP BitLocker: already on."; return }
    Save-BackupEntry 'bitlocker' '{"State":"Disabled"}'
    try {
        Enable-BitLocker -MountPoint 'C:' -EncryptionMethod XtsAes256 -UsedSpaceOnly -SkipHardwareTest -TpmProtector -ErrorAction Stop | Out-Null
        Write-Log "ENABLED: BitLocker on C: (TPM). Encrypting in the background."
    } catch {
        Write-Log "WARN BitLocker: $($_.Exception.Message)"
        Write-Log "NOTE: BitLocker needs Pro/Enterprise + TPM. On Home use Settings > Privacy & security > Device encryption."
    }
}

function Apply-AutoRun {
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    $old = (Get-ItemProperty $key -Name NoDriveTypeAutoRun -ErrorAction SilentlyContinue).NoDriveTypeAutoRun
    if ($old -eq 255) { Write-Log "SKIP AutoRun: already disabled."; return }
    Save-BackupEntry 'autorun' ("$old")
    New-Item -ItemType Directory -Path $key -Force | Out-Null
    Set-ItemProperty $key -Name NoDriveTypeAutoRun -Value 255 -Type DWord -ErrorAction Stop
    Write-Log "ENABLED: AutoRun disabled for removable drives."
}

function Apply-Lockout {
    $key = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters'
    $old = @{
        threshold=(Get-ItemProperty $key -Name lockoutthreshold -ErrorAction SilentlyContinue).lockoutthreshold
        duration=(Get-ItemProperty $key -Name lockoutduration -ErrorAction SilentlyContinue).lockoutduration
        window=(Get-ItemProperty $key -Name lockoutobservationwindow -ErrorAction SilentlyContinue).lockoutobservationwindow
    }
    if ($old.threshold -eq 5) { Write-Log "SKIP lockout: already set."; return }
    Save-BackupEntry 'lockout' ($old | ConvertTo-Json -Compress)
    New-Item -ItemType Directory -Path $key -Force | Out-Null
    Set-ItemProperty $key -Name lockoutthreshold -Value 5 -Type DWord
    Set-ItemProperty $key -Name lockoutduration -Value 15 -Type DWord
    Set-ItemProperty $key -Name lockoutobservationwindow -Value 15 -Type DWord
    Write-Log "ENABLED: account lockout after 5 failed tries for 15 min."
}

function Apply-OfficeWSH {
    $old = @{ office=@{}; wsh='' }
    foreach ($app in @('Word','Excel','PowerPoint','Outlook')) {
        $k = "HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\$app\Security"
        $old.office[$app] = (Get-ItemProperty $k -Name BlockContentExecutionFromInternet -ErrorAction SilentlyContinue).BlockContentExecutionFromInternet
        New-Item -ItemType Directory -Path $k -Force | Out-Null
        Set-ItemProperty $k -Name BlockContentExecutionFromInternet -Value 1 -Type DWord -ErrorAction SilentlyContinue
    }
    $k2 = 'HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings'
    $old.wsh = (Get-ItemProperty $k2 -Name Enabled -ErrorAction SilentlyContinue).Enabled
    New-Item -ItemType Directory -Path $k2 -Force | Out-Null
    Set-ItemProperty $k2 -Name Enabled -Value 0 -Type DWord -ErrorAction SilentlyContinue
    Save-BackupEntry 'officewsh' ($old | ConvertTo-Json -Compress)
    Write-Log "ENABLED: Office macros from internet blocked + Windows Script Host disabled."
}

function Apply-SecurityItem {
    param([string]$id)
    switch ($id) {
        'cloud'    { Apply-CloudProtection }
        'firewall' { Apply-FirewallBlock }
        'scan'     { Apply-ScanSchedule }
        'lock'     { Apply-AutoLock }
        'browsers' { Apply-BrowserHardening }
        'restore'  { Apply-SystemRestore }
        'bitlocker'{ Apply-BitLocker }
        'autorun'  { Apply-AutoRun }
        'lockout'  { Apply-Lockout }
        'officewsh'{ Apply-OfficeWSH }
    }
}

function Restore-SecurityEntry {
    param($row)
    try {
        switch ($row.Name) {
            'cloud' {
                $o = $row.Value | ConvertFrom-Json
                if ($null -ne $o.MAPS) { Set-MpPreference -MAPS $o.MAPS }
                if ($null -ne $o.SubmitSamplesConsent) { Set-MpPreference -SubmitSamplesConsent $o.SubmitSamplesConsent }
                if ($null -ne $o.CloudBlockLevel) { Set-MpPreference -CloudBlockLevel $o.CloudBlockLevel }
                Write-Log "RESTORED: cloud protection"
            }
            'firewall' {
                $o = $row.Value | ConvertFrom-Json
                foreach ($p in @('Domain','Private','Public')) { if ($o.$p) { Set-NetFirewallProfile -Name $p -DefaultInboundAction $o.$p.DefaultInboundAction -Enabled $o.$p.Enabled } }
                Write-Log "RESTORED: firewall settings"
            }
            'scan' { Set-MpPreference -ScanScheduleQuickScanTime $row.Value; Write-Log "RESTORED: scan schedule" }
            'lock' {
                $o = $row.Value | ConvertFrom-Json
                $d = 'HKCU:\Control Panel\Desktop'
                if ($null -ne $o.Active) { Set-ItemProperty $d -Name ScreenSaveActive -Value $o.Active }
                if ($null -ne $o.Secure) { Set-ItemProperty $d -Name ScreenSaverIsSecure -Value $o.Secure }
                if ($null -ne $o.Timeout) { Set-ItemProperty $d -Name ScreenSaveTimeOut -Value $o.Timeout }
                Write-Log "RESTORED: auto-lock"
            }
            'browsers' {
                $o = $row.Value | ConvertFrom-Json
                foreach ($b in @('edge','chrome')) {
                    $key = if ($b -eq 'edge') { $edgePolicies } else { $chromePolicies }
                    foreach ($pn in $o.$b.PSObject.Properties) {
                        if ($pn.Value -eq 'MISSING') { Remove-ItemProperty $key -Name $pn.Name -ErrorAction SilentlyContinue }
                        else { Set-ItemProperty $key -Name $pn.Name -Value ([int]$pn.Value) -Type DWord -ErrorAction SilentlyContinue }
                    }
                    $polKey = Get-Item $key -ErrorAction SilentlyContinue
                    if ($polKey -and $polKey.Property.Count -eq 0) { Remove-Item $key -Force -ErrorAction SilentlyContinue }
                }
                Write-Log "RESTORED: browser policies"
            }
            'restore' {
                $o = $row.Value | ConvertFrom-Json
                try { Unregister-ScheduledTask -TaskName 'WeeklySystemRestorePoint' -Confirm:$false -ErrorAction SilentlyContinue } catch { }
                $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
                if ($null -ne $o.Frequency -and $o.Frequency -ne '') { Set-ItemProperty $key -Name SystemRestorePointCreationFrequency -Value ([int]$o.Frequency) -Type DWord -ErrorAction SilentlyContinue }
                else { Remove-ItemProperty $key -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue }
                Write-Log "RESTORED: weekly restore task + frequency. Protection left ENABLED (safer)."
            }
            'bitlocker' { Write-Log "BitLocker left as-is (stays encrypted). Decrypt manually with the recovery key if you want it off." }
            'autorun' {
                $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
                if ($null -ne $row.Value -and $row.Value -ne '' -and $row.Value -ne 'null') { Set-ItemProperty $key -Name NoDriveTypeAutoRun -Value ([int]$row.Value) -Type DWord -ErrorAction SilentlyContinue }
                else { Remove-ItemProperty $key -Name NoDriveTypeAutoRun -ErrorAction SilentlyContinue }
                Write-Log "RESTORED: AutoRun setting"
            }
            'lockout' {
                $o = $row.Value | ConvertFrom-Json
                $key = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters'
                if ($null -ne $o.threshold) { Set-ItemProperty $key -Name lockoutthreshold -Value ([int]$o.threshold) -Type DWord -ErrorAction SilentlyContinue }
                if ($null -ne $o.duration) { Set-ItemProperty $key -Name lockoutduration -Value ([int]$o.duration) -Type DWord -ErrorAction SilentlyContinue }
                if ($null -ne $o.window) { Set-ItemProperty $key -Name lockoutobservationwindow -Value ([int]$o.window) -Type DWord -ErrorAction SilentlyContinue }
                Write-Log "RESTORED: account lockout policy"
            }
            'officewsh' {
                $o = $row.Value | ConvertFrom-Json
                foreach ($app in @('Word','Excel','PowerPoint','Outlook')) {
                    $k = "HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\$app\Security"
                    if ($o.office.PSObject.Properties[$app] -and $null -ne $o.office.$app) { Set-ItemProperty $k -Name BlockContentExecutionFromInternet -Value ([int]$o.office.$app) -Type DWord -ErrorAction SilentlyContinue }
                    else { Remove-ItemProperty $k -Name BlockContentExecutionFromInternet -ErrorAction SilentlyContinue }
                }
                $k2 = 'HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings'
                if ($null -ne $o.wsh -and $o.wsh -ne '') { Set-ItemProperty $k2 -Name Enabled -Value ([int]$o.wsh) -Type DWord -ErrorAction SilentlyContinue }
                else { Remove-ItemProperty $k2 -Name Enabled -ErrorAction SilentlyContinue }
                Write-Log "RESTORED: Office macro + Script Host settings"
            }
        }
        return $true
    } catch {
        Write-Log "ERROR restoring $($row.Name): $($_.Exception.Message)"
        return $false
    }
}

function Restore-Security {
    $rows = @(Get-Backup)
    if ($rows.Count -eq 0) { Write-Log "No security backup - nothing to restore."; return }
    Write-Log "=== Security restore started ==="
    foreach ($row in $rows) { [void](Restore-SecurityEntry $row) }
    Remove-Item $secBackupFile -Force -ErrorAction SilentlyContinue
    Write-Log "=== Security restore finished ==="
}

function Restore-SecurityItems {
    param([string[]]$ids)
    $rows = @(Get-Backup)
    if ($rows.Count -eq 0) { Write-Log "No security backup - nothing to restore."; return }
    $restored = 0
    $remaining = @()
    foreach ($row in $rows) {
        if ($ids -contains $row.Name) {
            [void](Restore-SecurityEntry $row)
            $restored++
        } else {
            $remaining += $row
        }
    }
    if ($restored -eq 0) { Write-Log "None of the ticked items had been applied (nothing to restore)."; return }
    if ($remaining.Count -eq 0) { Remove-Item $secBackupFile -Force -ErrorAction SilentlyContinue }
    else { $remaining | ConvertTo-Json | Set-Content -Path $secBackupFile -Encoding UTF8 }
    Write-Log "Restore checked finished ($restored item(s))."
}

# ================= MAINTENANCE =================
function Get-MaintBackup {
    if (Test-Path $maintBackupFile) { try { return @(Get-Content $maintBackupFile -Raw | ConvertFrom-Json) } catch { return @() } }
    return @()
}

function Save-MaintBackup {
    param([string]$name, [string]$value)
    $rows = @(Get-MaintBackup | Where-Object { $_.Name -ne $name })
    $rows += [PSCustomObject]@{ Name = $name; Value = $value }
    New-Item -ItemType Directory -Path (Split-Path $maintBackupFile) -Force | Out-Null
    $rows | ConvertTo-Json | Set-Content -Path $maintBackupFile -Encoding UTF8
}

function Invoke-CleanTemp {
    $targets = @( (Join-Path $env:TEMP '*'), (Join-Path $env:WINDIR 'Temp\*') )
    $count = 0
    foreach ($t in $targets) {
        Get-ChildItem -Path $t -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop; $count++ } catch { }
        }
    }
    Write-Log ("Cleared temp files ($count items removed).")
}

function Invoke-WUCleanup {
    Write-Log "Running Windows Update cleanup (StartComponentCleanup) - can take several minutes..."
    $out = & dism.exe /Online /Cleanup-Image /StartComponentCleanup 2>&1
    ($out | Out-String).Trim() -split "`r?`n" | Where-Object { $_ } | ForEach-Object { Write-Log ("    " + $_) }
    Write-Log "Windows Update cleanup done."
}

function Invoke-TrimSSD {
    try { Optimize-Volume -DriveLetter C -ReTrim -ErrorAction Stop | Out-Null; Write-Log "SSD re-trimmed (C:)." }
    catch { Write-Log ("WARN trim: " + $_.Exception.Message) }
}

function Invoke-FlushDNS {
    & ipconfig.exe /flushdns | Out-Null
    Write-Log "DNS cache flushed."
}

function Invoke-DisableGameDVR {
    $k = 'HKCU:\System\GameConfigStore'
    New-Item -ItemType Directory -Path $k -Force | Out-Null
    $old = (Get-ItemProperty $k -Name GameDVR_Enabled -ErrorAction SilentlyContinue).GameDVR_Enabled
    if ($old -eq 0) { Write-Log "SKIP Game DVR: already disabled."; return }
    Save-MaintBackup 'gamedvr' ("$old")
    Set-ItemProperty $k -Name GameDVR_Enabled -Value 0 -Type DWord
    Write-Log "ENABLED: Game DVR background recording disabled."
}

function Invoke-EnableStorageSense {
    $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'
    New-Item -ItemType Directory -Path $k -Force | Out-Null
    $old01 = (Get-ItemProperty $k -Name '01' -ErrorAction SilentlyContinue).'01'
    if ($old01 -eq 1) { Write-Log "SKIP Storage Sense: already enabled."; return }
    Save-MaintBackup 'storagesense' (@{ enabled = "$old01" } | ConvertTo-Json -Compress)
    Set-ItemProperty $k -Name '01' -Value 1 -Type DWord
    Set-ItemProperty $k -Name '04' -Value 1 -Type DWord
    Write-Log "ENABLED: Storage Sense (auto temp + recycle-bin cleanup)."
}

function Invoke-EmptyRecycleBin {
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    Write-Log "Emptied Recycle Bin."
}

function Invoke-ClearBrowserCache {
    $caches = @(
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache"
    )
    $n = 0
    foreach ($c in $caches) {
        if (Test-Path $c) {
            Get-ChildItem "$c\*" -Force -ErrorAction SilentlyContinue | ForEach-Object {
                try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop; $n++ } catch { }
            }
        }
    }
    Write-Log ("Cleared browser cache ($n items).")
}

function Invoke-StartupCleanup {
    $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    New-Item -ItemType Directory -Path $k -Force | Out-Null
    $hklm = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
    $backed = @{}
    if (Test-Path $k) { foreach ($v in (Get-Item $k).Property) { $backed[$k + '\' + $v] = (Get-ItemProperty $k -Name $v).$v } }
    Save-MaintBackup 'startupapps' ($backed | ConvertTo-Json -Compress)
    $disabled = 0
    if (Test-Path $k) {
        foreach ($v in @(Get-Item $k).Property) {
            try {
                $data = (Get-ItemProperty $k -Name $v).$v
                Set-ItemProperty $k -Name ($v + '.disabled') -Value $data
                Remove-ItemProperty $k -Name $v -ErrorAction Stop
                Write-Log ("Disabled startup: $v (current user)")
                $disabled++
            } catch { Write-Log ("WARN disable startup $v : " + $_.Exception.Message) }
        }
    }
    if (Test-Path $hklm) {
        Write-Log ("All-users (HKLM) startup entries (listed, NOT disabled): " + ((Get-Item $hklm).Property -join ', '))
    }
    Write-Log "Startup apps cleanup done ($disabled disabled, reversible)."
}

function Invoke-VfxPerformance {
    $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
    New-Item -ItemType Directory -Path $k -Force | Out-Null
    $old = (Get-ItemProperty $k -Name VisualFXSetting -ErrorAction SilentlyContinue).VisualFXSetting
    if ($old -eq 2) { Write-Log "SKIP visual effects: already best performance."; return }
    Save-MaintBackup 'vfxperf' ("$old")
    Set-ItemProperty $k -Name VisualFXSetting -Value 2 -Type DWord
    Write-Log "ENABLED: visual effects set to best performance."
}

function Invoke-EnableFastStartup {
    $k = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
    New-Item -ItemType Directory -Path $k -Force | Out-Null
    $old = (Get-ItemProperty $k -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
    if ($old -eq 1) { Write-Log "SKIP Fast Startup: already enabled."; return }
    Save-MaintBackup 'faststartup' ("$old")
    Set-ItemProperty $k -Name HiberbootEnabled -Value 1 -Type DWord
    Write-Log "ENABLED: Fast Startup (faster boot)."
}

function Invoke-DisableTips {
    $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    New-Item -ItemType Directory -Path $k -Force | Out-Null
    $names = @('SubscribedContent-310093Enabled','SubscribedContent-338387Enabled','SubscribedContent-338388Enabled','SubscribedContent-338389Enabled','SubscribedContent-353694Enabled','SubscribedContent-353696Enabled')
    $old = @{}; $already = $true
    foreach ($n in $names) {
        $cur = (Get-ItemProperty $k -Name $n -ErrorAction SilentlyContinue).$n
        $old[$n] = "$cur"
        if ($cur -ne 0) { $already = $false }
    }
    if ($already) { Write-Log "SKIP tips: already disabled."; return }
    Save-MaintBackup 'tips' ($old | ConvertTo-Json -Compress)
    foreach ($n in $names) { Set-ItemProperty $k -Name $n -Value 0 -Type DWord -ErrorAction SilentlyContinue }
    Write-Log "ENABLED: Windows tips & suggestions disabled."
}

function Invoke-PowerHighPerf {
    $out = (powercfg /getactivescheme)
    $m = [regex]::Match(($out -join ' '), '([0-9a-fA-F-]{36})')
    $oldGuid = if ($m.Success) { $m.Groups[1].Value } else { '381b4222-f694-41f0-9685-ff5bb260df2e' }
    $highGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    if ($oldGuid -eq $highGuid) { Write-Log "SKIP power plan: already High performance."; return }
    Save-MaintBackup 'powerplan' $oldGuid
    powercfg /setactive $highGuid
    Write-Log "ENABLED: power plan set to High performance (battery drains faster on laptops)."
}

function Run-MaintenanceItem {
    param([string]$id)
    switch ($id) {
        'cleantemp'    { Invoke-CleanTemp }
        'wucleanup'    { Invoke-WUCleanup }
        'trimssd'      { Invoke-TrimSSD }
        'flushdns'     { Invoke-FlushDNS }
        'gamedvr'      { Invoke-DisableGameDVR }
        'storagesense' { Invoke-EnableStorageSense }
        'recyclebin'   { Invoke-EmptyRecycleBin }
        'browscache'   { Invoke-ClearBrowserCache }
        'startupapps'  { Invoke-StartupCleanup }
        'vfxperf'      { Invoke-VfxPerformance }
        'faststartup'  { Invoke-EnableFastStartup }
        'tips'         { Invoke-DisableTips }
        'powerplan'    { Invoke-PowerHighPerf }
    }
}

function Restore-Maintenance {
    $rows = @(Get-MaintBackup)
    if ($rows.Count -eq 0) { Write-Log "No maintenance backup - nothing to restore."; return }
    Write-Log "=== Maintenance restore started ==="
    foreach ($row in $rows) {
        try {
            switch ($row.Name) {
                'gamedvr' {
                    $k = 'HKCU:\System\GameConfigStore'
                    if ($null -ne $row.Value -and $row.Value -ne '' -and $row.Value -ne 'null') { Set-ItemProperty $k -Name GameDVR_Enabled -Value ([int]$row.Value) -Type DWord -ErrorAction SilentlyContinue }
                    else { Remove-ItemProperty $k -Name GameDVR_Enabled -ErrorAction SilentlyContinue }
                    Write-Log "RESTORED: Game DVR"
                }
                'storagesense' {
                    $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'
                    $o = $row.Value | ConvertFrom-Json
                    if ($null -ne $o.enabled -and $o.enabled -ne '' -and $o.enabled -ne 'null') { Set-ItemProperty $k -Name '01' -Value ([int]$o.enabled) -Type DWord -ErrorAction SilentlyContinue }
                    else { Remove-ItemProperty $k -Name '01' -ErrorAction SilentlyContinue }
                    Write-Log "RESTORED: Storage Sense"
                }
                'vfxperf' {
                    $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
                    if ($null -ne $row.Value -and $row.Value -ne '' -and $row.Value -ne 'null') { Set-ItemProperty $k -Name VisualFXSetting -Value ([int]$row.Value) -Type DWord -ErrorAction SilentlyContinue }
                    else { Remove-ItemProperty $k -Name VisualFXSetting -ErrorAction SilentlyContinue }
                    Write-Log "RESTORED: visual effects"
                }
                'startupapps' {
                    $o = $row.Value | ConvertFrom-Json
                    $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
                    foreach ($p in $o.PSObject.Properties) {
                        $valname = $p.Name -replace '^.*\\', ''
                        $orig = $valname -replace '\.disabled$', ''
                        $data = $p.Value
                        if ($data -and $data -ne 'null') { Set-ItemProperty $k -Name $orig -Value $data -ErrorAction SilentlyContinue }
                        Remove-ItemProperty $k -Name $valname -ErrorAction SilentlyContinue
                    }
                    Write-Log "RESTORED: startup apps"
                }
                'faststartup' {
                    $k = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
                    if ($null -ne $row.Value -and $row.Value -ne '' -and $row.Value -ne 'null') { Set-ItemProperty $k -Name HiberbootEnabled -Value ([int]$row.Value) -Type DWord -ErrorAction SilentlyContinue }
                    else { Remove-ItemProperty $k -Name HiberbootEnabled -ErrorAction SilentlyContinue }
                    Write-Log "RESTORED: Fast Startup"
                }
                'tips' {
                    $o = $row.Value | ConvertFrom-Json
                    $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
                    foreach ($n in @('SubscribedContent-310093Enabled','SubscribedContent-338387Enabled','SubscribedContent-338388Enabled','SubscribedContent-338389Enabled','SubscribedContent-353694Enabled','SubscribedContent-353696Enabled')) {
                        if ($o.PSObject.Properties[$n] -and $null -ne $o.$n -and $o.$n -ne '' -and $o.$n -ne 'null') { Set-ItemProperty $k -Name $n -Value ([int]$o.$n) -Type DWord -ErrorAction SilentlyContinue }
                        else { Remove-ItemProperty $k -Name $n -ErrorAction SilentlyContinue }
                    }
                    Write-Log "RESTORED: tips & suggestions"
                }
                'powerplan' {
                    if ($row.Value -and $row.Value -match '^[0-9a-fA-F-]{36}$') { powercfg /setactive $row.Value | Out-Null }
                    Write-Log "RESTORED: power plan"
                }
            }
        } catch { Write-Log "ERROR restoring $($row.Name): $($_.Exception.Message)" }
    }
    Remove-Item $maintBackupFile -Force -ErrorAction SilentlyContinue
    Write-Log "=== Maintenance restore finished ==="
}

function Review-Maintenance {
    Write-Log "-- Maintenance --"
    $gdv = (Get-ItemProperty 'HKCU:\System\GameConfigStore' -Name GameDVR_Enabled -ErrorAction SilentlyContinue).GameDVR_Enabled
    Write-Log ("  Game DVR        : " + $(if ($gdv -eq 0) { 'off (good)' } else { 'on (running)' }))
    $ss = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' -Name '01' -ErrorAction SilentlyContinue).'01'
    Write-Log ("  Storage Sense   : " + $(if ($ss -eq 1) { 'on' } else { 'off' }))
    $t = (Get-ChildItem $env:TEMP -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    Write-Log ("  Temp files      : ~{0} MB in {1}" -f [math]::Round($t/1MB, 1), $env:TEMP)
    $fs = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
    Write-Log ("  Fast Startup    : " + $(if ($fs -eq 1) { 'on' } else { 'off' }))
    $active = (powercfg /getactivescheme | Out-String)
    Write-Log ("  Power plan      : " + (($active -split ':')[-1]).Trim())
}

# ================= SYSTEM REPAIR =================
function Invoke-SfcScan {
    Write-Log "Running sfc /scannow - verifies and repairs system files (may take several minutes)..."
    $out = & sfc.exe /scannow 2>&1
    ($out | Out-String).Trim() -split "`r?`n" | Where-Object { $_ } | ForEach-Object { Write-Log ("    " + $_) }
    Write-Log "sfc /scannow done."
}

function Invoke-DismRepair {
    Write-Log "Running DISM /restorehealth - repairs the Windows image (can take 10-20+ min, may need internet)..."
    $out = & dism.exe /Online /Cleanup-Image /RestoreHealth 2>&1
    ($out | Out-String).Trim() -split "`r?`n" | Where-Object { $_ } | ForEach-Object { Write-Log ("    " + $_) }
    Write-Log "DISM /restorehealth done."
}

function Invoke-Chkdsk {
    Write-Log "Scheduling disk check (chkdsk C: /f) - it will run at the next restart..."
    $out = "Y" | chkdsk.exe C: /f 2>&1
    ($out | Out-String).Trim() -split "`r?`n" | Where-Object { $_ } | ForEach-Object { Write-Log ("    " + $_) }
    Write-Log "chkdsk scheduled. Restart the PC to let it run."
}

function Run-RepairItem {
    param([string]$id)
    switch ($id) {
        'sfc'    { Invoke-SfcScan }
        'dism'   { Invoke-DismRepair }
        'chkdsk' { Invoke-Chkdsk }
    }
}

function Review-Security {
    $sb = New-Object System.Text.StringBuilder
    function Add-RevLine { param([string]$line) [void]$sb.AppendLine($line); Write-Log $line }
    function Get-RevVal { param($v, [string]$fb='n/a') if ($null -eq $v) { return $fb } return $v }

    Add-RevLine "=== Security Review - $env:COMPUTERNAME ==="
    $st = Get-MpComputerStatus
    $mp = Get-MpSetting
    Add-RevLine ("  Real-time protection : " + (Get-RevVal $st.RealTimeProtectionEnabled))
    Add-RevLine ("  Cloud protection MAPS: " + (Get-RevVal $mp.MAPS) + "  (2 = recommended)")
    Add-RevLine ("  Signatures age (days): " + (Get-RevVal ([math]::Round(((Get-Date) - $st.AntivirusSignatureLastUpdated).TotalDays, 1))))
    foreach ($profile in @('Domain','Private','Public')) { $f = Get-NetFirewallProfile -Name $profile; Add-RevLine ("  Firewall {0}: defaultInbound={1}" -f $profile, $f.DefaultInboundAction) }
    $rdp = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -ErrorAction SilentlyContinue).fDenyTSConnections
    Add-RevLine ("  Remote Desktop      : " + $(if ($rdp -eq 0) { 'ENABLED' } else { 'disabled (good)' }))
    $edgeDl = (Get-ItemProperty $edgePolicies -Name DownloadRestrictions -ErrorAction SilentlyContinue).DownloadRestrictions
    $chromeDl = (Get-ItemProperty $chromePolicies -Name DownloadRestrictions -ErrorAction SilentlyContinue).DownloadRestrictions
    Add-RevLine ("  Browser hardening   : Edge=" + $(if ($edgeDl -eq 2) { 'OK' } else { 'off' }) + "  Chrome=" + $(if ($chromeDl -eq 2) { 'OK' } else { 'off' }))
    $rps = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue)
    Add-RevLine ("  Restore points     : " + $(if ($rps.Count -gt 0) { $rps.Count } else { 'none (protection likely OFF)' }))
    $bl = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction SilentlyContinue
    Add-RevLine ("  BitLocker C:        : " + $(if ($bl) { $bl.ProtectionStatus } else { 'n/a' }))
    $ar = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name NoDriveTypeAutoRun -ErrorAction SilentlyContinue).NoDriveTypeAutoRun
    Add-RevLine ("  AutoRun disabled    : " + $(if ($ar -eq 255) { 'yes' } else { 'no' }))
    $lt = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters' -Name lockoutthreshold -ErrorAction SilentlyContinue).lockoutthreshold
    Add-RevLine ("  Account lockout     : " + $(if ($lt -eq 5) { '5 tries' } else { 'off/other (' + (Get-RevVal $lt) + ')' }))
    $wsh = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings' -Name Enabled -ErrorAction SilentlyContinue).Enabled
    Add-RevLine ("  Script Host (VBS)   : " + $(if ($wsh -eq 0) { 'disabled' } else { 'enabled' }))
    New-Item -ItemType Directory -Path $secDir -Force | Out-Null
    $sb.ToString() | Set-Content -Path $secReviewFile -Encoding UTF8
    Write-Log ("Review report saved to: " + $secReviewFile)
}

# ================= UI =================
function Show-Help {
    $hf = New-Object System.Windows.Forms.Form
    $hf.Text = 'System Optimizer - Help / Settings Guide'
    $hf.ClientSize = New-Object System.Drawing.Size(860, 760)
    $hf.StartPosition = 'CenterParent'
    $hf.MinimizeBox = $false
    $hf.Font = New-Object System.Drawing.Font('Segoe UI', 10)

    $rtb = New-Object System.Windows.Forms.RichTextBox
    $rtb.ReadOnly = $true
    $rtb.WordWrap = $true
    $rtb.ScrollBars = 'Vertical'
    $rtb.Dock = 'Fill'
    $rtb.BackColor = [System.Drawing.Color]::White
    $rtb.ForeColor = [System.Drawing.Color]::Black
    $rtb.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $rtb.BorderStyle = 'None'
    $hf.Controls.Add($rtb)

    $cTitle   = [System.Drawing.Color]::FromArgb(31,78,121)
    $cHeader  = [System.Drawing.Color]::FromArgb(0,90,158)
    $cSub     = [System.Drawing.Color]::FromArgb(31,78,121)
    $cItem    = [System.Drawing.Color]::FromArgb(40,40,40)
    $cBody    = [System.Drawing.Color]::FromArgb(60,60,60)
    $cNote    = [System.Drawing.Color]::FromArgb(150,110,0)

    function Emit-Help([string]$text, [string]$style) {
        $rtb.SelectionStart = $rtb.TextLength
        $rtb.SelectionLength = 0
        $b = [System.Drawing.FontStyle]::Bold
        $r = [System.Drawing.FontStyle]::Regular
        $i = [System.Drawing.FontStyle]::Italic
        switch ($style) {
            'title'  { $rtb.SelectionFont = New-Object System.Drawing.Font('Segoe UI', 15, $b); $rtb.SelectionColor = $cTitle }
            'header' { $rtb.SelectionFont = New-Object System.Drawing.Font('Segoe UI', 12, $b); $rtb.SelectionColor = $cHeader }
            'sub'    { $rtb.SelectionFont = New-Object System.Drawing.Font('Segoe UI', 11, $b); $rtb.SelectionColor = $cSub }
            'item'   { $rtb.SelectionFont = New-Object System.Drawing.Font('Segoe UI', 10, $b); $rtb.SelectionColor = $cItem }
            'note'   { $rtb.SelectionFont = New-Object System.Drawing.Font('Segoe UI', 10, $i); $rtb.SelectionColor = $cNote }
            default  { $rtb.SelectionFont = New-Object System.Drawing.Font('Segoe UI', 10, $r); $rtb.SelectionColor = $cBody }
        }
        $rtb.AppendText($text + "`r`n")
    }

    foreach ($raw in ($helpText -split "`r?`n")) {
        $ts = $raw.Trim()
        if ($ts -match '^(=|-){4,}$') { Emit-Help '' 'body'; continue }
        if ($ts -eq 'System Optimizer - User Guide') { Emit-Help 'System Optimizer - User Guide' 'title'; continue }
        if ($ts -match '^(TAB [12] |MASTER BUTTONS|WHERE THINGS ARE STORED|NOTES FOR A FRESH|UNDO AND REVERT|SAFE services|OPTIONAL services|Buttons:)') { Emit-Help $ts 'header'; continue }
        if ($ts -match '^[0-9]{1,2}\. ') { Emit-Help $ts 'item'; continue }
        if ($ts -match '^(IMPORTANT|Note|Tradeoff|Restore does NOT|Warning)') { Emit-Help $ts 'note'; continue }
        Emit-Help $raw 'body'
    }

    [void]$hf.ShowDialog()
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'System Optimizer - Performance + Security'
$form.ClientSize = New-Object System.Drawing.Size(900, 660)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(10, 10)
$tabs.Size = New-Object System.Drawing.Size(880, 420)

# --- Tab 1: Performance & Services ---
$tabPerf = New-Object System.Windows.Forms.TabPage
$tabPerf.Text = 'Performance & Services'
$tabPerf.Padding = New-Object System.Windows.Forms.Padding(6)
$tabPerf.AutoScroll = $true

$gbSafe = New-Object System.Windows.Forms.GroupBox
$gbSafe.Text = 'SAFE services (recommended)'
$gbSafe.Location = New-Object System.Drawing.Point(6, 6)
$gbSafe.Size = New-Object System.Drawing.Size(420, 320)
$flowSafe = New-Object System.Windows.Forms.FlowLayoutPanel
$flowSafe.Location = New-Object System.Drawing.Point(10, 22)
$flowSafe.Size = New-Object System.Drawing.Size(400, 290)
$flowSafe.AutoScroll = $true; $flowSafe.WrapContents = $false; $flowSafe.FlowDirection = 'TopDown'
$gbSafe.Controls.Add($flowSafe)

$gbOpt = New-Object System.Windows.Forms.GroupBox
$gbOpt.Text = 'OPTIONAL services (may affect features)'
$gbOpt.Location = New-Object System.Drawing.Point(434, 6)
$gbOpt.Size = New-Object System.Drawing.Size(420, 320)
$flowOpt = New-Object System.Windows.Forms.FlowLayoutPanel
$flowOpt.Location = New-Object System.Drawing.Point(10, 22)
$flowOpt.Size = New-Object System.Drawing.Size(400, 290)
$flowOpt.AutoScroll = $true; $flowOpt.WrapContents = $false; $flowOpt.FlowDirection = 'TopDown'
$gbOpt.Controls.Add($flowOpt)

foreach ($n in $safeServices) {
    $disp = (Get-Service -Name $n -ErrorAction SilentlyContinue).DisplayName
    $label = if ($disp) { "$n  ($disp)" } else { $n }
    $cb = New-Object System.Windows.Forms.CheckBox; $cb.Text = $label; $cb.Font = New-Object System.Drawing.Font('Consolas', 9)
    $cb.AutoSize = $true; $cb.Checked = $true; $cb.Tag = $n
    [void]$script:svcChecks.Add($cb); $flowSafe.Controls.Add($cb)
}
foreach ($n in $optionalServices) {
    $disp = (Get-Service -Name $n -ErrorAction SilentlyContinue).DisplayName
    $label = if ($disp) { "$n  ($disp)" } else { $n }
    $cb = New-Object System.Windows.Forms.CheckBox; $cb.Text = $label; $cb.Font = New-Object System.Drawing.Font('Consolas', 9)
    $cb.AutoSize = $true; $cb.Checked = $false; $cb.Tag = $n
    [void]$script:svcChecks.Add($cb); $flowOpt.Controls.Add($cb)
}

$btnDisable = New-Object System.Windows.Forms.Button; $btnDisable.Text = 'Disable services (selected)'; $btnDisable.Size = New-Object System.Drawing.Size(160,30); $btnDisable.Location = New-Object System.Drawing.Point(6, 336)
$btnRestoreSvc = New-Object System.Windows.Forms.Button; $btnRestoreSvc.Text = 'Restore services'; $btnRestoreSvc.Size = New-Object System.Drawing.Size(130,30); $btnRestoreSvc.Location = New-Object System.Drawing.Point(174, 336)
$btnVerifySvc = New-Object System.Windows.Forms.Button; $btnVerifySvc.Text = 'Verify services'; $btnVerifySvc.Size = New-Object System.Drawing.Size(130,30); $btnVerifySvc.Location = New-Object System.Drawing.Point(312, 336)
$btnRestoreOpt = New-Object System.Windows.Forms.Button; $btnRestoreOpt.Text = 'Restore optional only'; $btnRestoreOpt.Size = New-Object System.Drawing.Size(150,30); $btnRestoreOpt.Location = New-Object System.Drawing.Point(450, 336)

$tabPerf.Controls.Add($gbSafe); $tabPerf.Controls.Add($gbOpt)
$tabPerf.Controls.Add($btnDisable); $tabPerf.Controls.Add($btnRestoreSvc); $tabPerf.Controls.Add($btnVerifySvc); $tabPerf.Controls.Add($btnRestoreOpt)

$lblOptHint = New-Object System.Windows.Forms.Label
$lblOptHint.Text = "TIP: OPTIONAL services can disable printing, Remote Desktop, Bluetooth, search or scanners. If a feature stops working, use 'Restore optional only'."
$lblOptHint.Location = New-Object System.Drawing.Point(8, 374)
$lblOptHint.Size = New-Object System.Drawing.Size(860, 40)
$lblOptHint.ForeColor = [System.Drawing.Color]::FromArgb(150,110,0)
$tabPerf.Controls.Add($lblOptHint)

$tip = New-Object System.Windows.Forms.ToolTip
$tip.SetToolTip($gbOpt, "Optional: printing, Remote Desktop, Bluetooth, search, scanners, biometrics, cellular. These may affect a feature you use.")
$tip.SetToolTip($btnRestoreOpt, "Re-enable only the OPTIONAL services you disabled (print, Remote Desktop, Bluetooth, etc.). Safe services stay as-is.")

# --- Tab 2: Security & Hardening ---
$tabSec = New-Object System.Windows.Forms.TabPage
$tabSec.Text = 'Security & Hardening'
$tabSec.Padding = New-Object System.Windows.Forms.Padding(6)
$tabSec.AutoScroll = $true

$gbSec = New-Object System.Windows.Forms.GroupBox
$gbSec.Text = 'Hardening items (tick to apply)'
$gbSec.Location = New-Object System.Drawing.Point(6, 6)
$gbSec.Size = New-Object System.Drawing.Size(852, 320)
$flowSec = New-Object System.Windows.Forms.FlowLayoutPanel
$flowSec.Location = New-Object System.Drawing.Point(10, 22)
$flowSec.Size = New-Object System.Drawing.Size(830, 290)
$flowSec.AutoScroll = $true; $flowSec.WrapContents = $false; $flowSec.FlowDirection = 'TopDown'
foreach ($it in $secItems) {
    $cb = New-Object System.Windows.Forms.CheckBox; $cb.Text = $it.text; $cb.AutoSize = $true; $cb.Checked = $true; $cb.Tag = $it.id
    [void]$script:secChecks.Add($cb); $flowSec.Controls.Add($cb)
}
$gbSec.Controls.Add($flowSec)

$btnApplySec = New-Object System.Windows.Forms.Button; $btnApplySec.Text = 'Apply security (selected)'; $btnApplySec.Size = New-Object System.Drawing.Size(150,30); $btnApplySec.Location = New-Object System.Drawing.Point(6, 336)
$btnRestoreSec = New-Object System.Windows.Forms.Button; $btnRestoreSec.Text = 'Restore security'; $btnRestoreSec.Size = New-Object System.Drawing.Size(130,30); $btnRestoreSec.Location = New-Object System.Drawing.Point(164, 336)
$btnReviewSec = New-Object System.Windows.Forms.Button; $btnReviewSec.Text = 'Security review'; $btnReviewSec.Size = New-Object System.Drawing.Size(130,30); $btnReviewSec.Location = New-Object System.Drawing.Point(302, 336)
$btnRestoreCheckedSec = New-Object System.Windows.Forms.Button; $btnRestoreCheckedSec.Text = 'Restore checked'; $btnRestoreCheckedSec.Size = New-Object System.Drawing.Size(150,30); $btnRestoreCheckedSec.Location = New-Object System.Drawing.Point(440, 336)

$tabSec.Controls.Add($gbSec); $tabSec.Controls.Add($btnApplySec); $tabSec.Controls.Add($btnRestoreSec); $tabSec.Controls.Add($btnReviewSec); $tabSec.Controls.Add($btnRestoreCheckedSec)

# --- Tab 3: Maintenance & Cleanup ---
$tabMaint = New-Object System.Windows.Forms.TabPage
$tabMaint.Text = 'Maintenance & Cleanup'
$tabMaint.Padding = New-Object System.Windows.Forms.Padding(6)
$tabMaint.AutoScroll = $true

$gbMaint = New-Object System.Windows.Forms.GroupBox
$gbMaint.Text = 'Cleanup & maintenance items (tick to run)'
$gbMaint.Location = New-Object System.Drawing.Point(6, 6)
$gbMaint.Size = New-Object System.Drawing.Size(852, 320)
$flowMaint = New-Object System.Windows.Forms.FlowLayoutPanel
$flowMaint.Location = New-Object System.Drawing.Point(10, 22)
$flowMaint.Size = New-Object System.Drawing.Size(830, 290)
$flowMaint.AutoScroll = $true; $flowMaint.WrapContents = $false; $flowMaint.FlowDirection = 'TopDown'
foreach ($it in $maintItems) {
    $safe = @('cleantemp','wucleanup','trimssd','flushdns','gamedvr','faststartup','tips') -contains $it.id
    $cb = New-Object System.Windows.Forms.CheckBox; $cb.Text = $it.text; $cb.AutoSize = $true; $cb.Checked = $safe; $cb.Tag = $it.id
    [void]$script:maintChecks.Add($cb); $flowMaint.Controls.Add($cb)
}
$gbMaint.Controls.Add($flowMaint)

$btnMaintRun = New-Object System.Windows.Forms.Button; $btnMaintRun.Text = 'Run selected cleanup'; $btnMaintRun.Size = New-Object System.Drawing.Size(150,30); $btnMaintRun.Location = New-Object System.Drawing.Point(6, 336)
$btnMaintRestore = New-Object System.Windows.Forms.Button; $btnMaintRestore.Text = 'Restore settings'; $btnMaintRestore.Size = New-Object System.Drawing.Size(140,30); $btnMaintRestore.Location = New-Object System.Drawing.Point(164, 336)
$btnMaintReport = New-Object System.Windows.Forms.Button; $btnMaintReport.Text = 'Cleanup report'; $btnMaintReport.Size = New-Object System.Drawing.Size(130,30); $btnMaintReport.Location = New-Object System.Drawing.Point(312, 336)

$lblMaintHint = New-Object System.Windows.Forms.Label
$lblMaintHint.Text = "TIP: items 1-5 and 11-12 are safe and pre-ticked. Items 6-10 and 13 are optional/off (may delete recoverable files, change visuals/power, or auto-clean restore points). Reversible settings can be undone with 'Restore settings'."
$lblMaintHint.Location = New-Object System.Drawing.Point(8, 374)
$lblMaintHint.Size = New-Object System.Drawing.Size(860, 40)
$lblMaintHint.ForeColor = [System.Drawing.Color]::FromArgb(150,110,0)
$tabMaint.Controls.Add($gbMaint)
$tabMaint.Controls.Add($btnMaintRun); $tabMaint.Controls.Add($btnMaintRestore); $tabMaint.Controls.Add($btnMaintReport)
$tabMaint.Controls.Add($lblMaintHint)

$tabs.TabPages.Add($tabPerf); $tabs.TabPages.Add($tabSec); $tabs.TabPages.Add($tabMaint)

# --- Tab 4: System Repair ---
$tabRepair = New-Object System.Windows.Forms.TabPage
$tabRepair.Text = 'System Repair'
$tabRepair.Padding = New-Object System.Windows.Forms.Padding(6)
$tabRepair.AutoScroll = $true

$gbRepair = New-Object System.Windows.Forms.GroupBox
$gbRepair.Text = 'Repair tools (tick to run)'
$gbRepair.Location = New-Object System.Drawing.Point(6, 6)
$gbRepair.Size = New-Object System.Drawing.Size(852, 200)
$flowRepair = New-Object System.Windows.Forms.FlowLayoutPanel
$flowRepair.Location = New-Object System.Drawing.Point(10, 22)
$flowRepair.Size = New-Object System.Drawing.Size(830, 170)
$flowRepair.AutoScroll = $true; $flowRepair.WrapContents = $false; $flowRepair.FlowDirection = 'TopDown'

$repairItems = @(
    @{ id='sfc';    text='Verify and repair system files (sfc /scannow)' },
    @{ id='dism';   text='Repair the Windows image (DISM /restorehealth)' },
    @{ id='chkdsk'; text='Check disk for errors (chkdsk C: /f) - REQUIRES RESTART' }
)
foreach ($it in $repairItems) {
    $cb = New-Object System.Windows.Forms.CheckBox; $cb.Text = $it.text; $cb.AutoSize = $true
    $cb.Checked = ($it.id -ne 'chkdsk'); $cb.Tag = $it.id
    [void]$script:repairChecks.Add($cb); $flowRepair.Controls.Add($cb)
}
$gbRepair.Controls.Add($flowRepair)

$btnRepairRun = New-Object System.Windows.Forms.Button; $btnRepairRun.Text = 'Run selected repairs'; $btnRepairRun.Size = New-Object System.Drawing.Size(160,30); $btnRepairRun.Location = New-Object System.Drawing.Point(6, 214)

$lblRepairHint = New-Object System.Windows.Forms.Label
$lblRepairHint.Text = "NOTE: repairs can take a long time (sfc 5-10 min, DISM 10-20+ min). chkdsk needs a restart. Repairs are NOT part of 'Apply ALL' - run them here when needed."
$lblRepairHint.Location = New-Object System.Drawing.Point(8, 252)
$lblRepairHint.Size = New-Object System.Drawing.Size(860, 40)
$lblRepairHint.ForeColor = [System.Drawing.Color]::FromArgb(150,110,0)
$tabRepair.Controls.Add($gbRepair)
$tabRepair.Controls.Add($btnRepairRun)
$tabRepair.Controls.Add($lblRepairHint)

$tabs.TabPages.Add($tabRepair)
$form.Controls.Add($tabs)

# --- bottom master controls ---
$btnApplyAll = New-Object System.Windows.Forms.Button; $btnApplyAll.Text = 'Apply ALL selected'; $btnApplyAll.Size = New-Object System.Drawing.Size(180,34); $btnApplyAll.Location = New-Object System.Drawing.Point(10, 442)
$btnRestoreAll = New-Object System.Windows.Forms.Button; $btnRestoreAll.Text = 'Restore ALL to defaults'; $btnRestoreAll.Size = New-Object System.Drawing.Size(190,34); $btnRestoreAll.Location = New-Object System.Drawing.Point(200, 442)
$btnReviewAll = New-Object System.Windows.Forms.Button; $btnReviewAll.Text = 'Full review / verify'; $btnReviewAll.Size = New-Object System.Drawing.Size(160,34); $btnReviewAll.Location = New-Object System.Drawing.Point(400, 442)
$tip.SetToolTip($btnApplyAll, "Applies EVERYTHING you ticked on both tabs: services AND security. Use this for the full recommended setup in one click.")
$tip.SetToolTip($btnRestoreAll, "Returns ALL services and security settings to their original state.")
$tip.SetToolTip($btnReviewAll, "Runs a full check of both services and security settings.")
$btnHelp = New-Object System.Windows.Forms.Button; $btnHelp.Text = 'Help / settings guide'; $btnHelp.Size = New-Object System.Drawing.Size(170,34); $btnHelp.Location = New-Object System.Drawing.Point(570, 442)

$lblLog = New-Object System.Windows.Forms.Label; $lblLog.Text = 'Log:'; $lblLog.Location = New-Object System.Drawing.Point(10, 486)

$script:logBox = New-Object System.Windows.Forms.TextBox
$script:logBox.Multiline = $true; $script:logBox.ReadOnly = $true; $script:logBox.ScrollBars = 'Vertical'
$script:logBox.BackColor = [System.Drawing.Color]::FromArgb(32,32,32); $script:logBox.ForeColor = [System.Drawing.Color]::White
$script:logBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$script:logBox.Location = New-Object System.Drawing.Point(10, 506); $script:logBox.Size = New-Object System.Drawing.Size(880, 142)

$form.Controls.Add($btnApplyAll); $form.Controls.Add($btnRestoreAll); $form.Controls.Add($btnReviewAll)
$form.Controls.Add($btnHelp)
$form.Controls.Add($lblLog); $form.Controls.Add($script:logBox)

# ================= handlers =================
$btnDisable.add_Click({
    $names = @($script:svcChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    if ($names.Count -eq 0) { [void][System.Windows.Forms.MessageBox]::Show('Select at least one service.', 'Nothing selected', 'OK', 'Warning'); return }
    New-Item -ItemType Directory -Path $wsDir -Force | Out-Null
    Write-Log '=== Services optimize started ==='; Backup-Services; Disable-Services $names; Write-Log '=== Services optimize finished ==='
    [void][System.Windows.Forms.MessageBox]::Show("Done. $($names.Count) services processed. Reboot recommended.", 'Finished', 'OK', 'Information')
})

$btnRestoreSvc.add_Click({ Write-Log '=== Services restore ==='; Restore-Services; Write-Log '=== finished ==='; [void][System.Windows.Forms.MessageBox]::Show('Services restore complete.', 'Finished', 'OK', 'Information') })
$btnVerifySvc.add_Click({ Write-Log '--- Verify services ---'; Verify-Services })
$btnRestoreOpt.add_Click({ Write-Log '--- Restore optional services ---'; Restore-OptionalServices; [void][System.Windows.Forms.MessageBox]::Show('Optional services restored (print, Remote Desktop, Bluetooth, etc.).', 'Finished', 'OK', 'Information') })

$btnApplySec.add_Click({
    $ids = @($script:secChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    if ($ids.Count -eq 0) { [void][System.Windows.Forms.MessageBox]::Show('Tick at least one hardening item.', 'Nothing selected', 'OK', 'Warning'); return }
    New-Item -ItemType Directory -Path $secDir -Force | Out-Null
    Write-Log '=== Security hardening started ==='
    foreach ($id in $ids) { Apply-SecurityItem $id }
    Write-Log '=== Security hardening finished ==='
    [void][System.Windows.Forms.MessageBox]::Show('Hardening applied. A reboot is recommended.', 'Finished', 'OK', 'Information')
})

$btnRestoreSec.add_Click({ Write-Log '--- Restore security ---'; Restore-Security; [void][System.Windows.Forms.MessageBox]::Show('Security restore complete.', 'Finished', 'OK', 'Information') })
$btnReviewSec.add_Click({ Write-Log '--- Security review ---'; Review-Security })
$btnRestoreCheckedSec.add_Click({
    $ids = @($script:secChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    if ($ids.Count -eq 0) { [void][System.Windows.Forms.MessageBox]::Show('Tick the hardening items you want to restore.', 'Nothing selected', 'OK', 'Warning'); return }
    Write-Log '--- Restore checked (security) ---'
    Restore-SecurityItems $ids
    [void][System.Windows.Forms.MessageBox]::Show('Checked items restored to their previous settings.', 'Finished', 'OK', 'Information')
})

$btnApplyAll.add_Click({
    New-Item -ItemType Directory -Path $wsDir -Force | Out-Null
    New-Item -ItemType Directory -Path $secDir -Force | Out-Null
    Write-Log '===== APPLY ALL ====='
    $svc = @($script:svcChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    if ($svc.Count -gt 0) { Backup-Services; Disable-Services $svc }
    foreach ($id in @($script:secChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })) { Apply-SecurityItem $id }
    foreach ($id in @($script:maintChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })) { Run-MaintenanceItem $id }
    Write-Log '===== APPLY ALL finished ====='
    [void][System.Windows.Forms.MessageBox]::Show('All selected items applied. A reboot is recommended.', 'Finished', 'OK', 'Information')
})

$btnRestoreAll.add_Click({
    Write-Log '===== RESTORE ALL ====='
    Restore-Services
    Restore-Security
    Restore-Maintenance
    Write-Log '===== RESTORE ALL finished ====='
    [void][System.Windows.Forms.MessageBox]::Show('All settings restored to defaults.', 'Finished', 'OK', 'Information')
})

$btnReviewAll.add_Click({ Write-Log '--- Full review ---'; Verify-Services; Review-Security; Review-Maintenance })
$btnHelp.add_Click({ Show-Help })

$btnMaintRun.add_Click({
    $ids = @($script:maintChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    if ($ids.Count -eq 0) { [void][System.Windows.Forms.MessageBox]::Show('Tick at least one cleanup item.', 'Nothing selected', 'OK', 'Warning'); return }
    Write-Log '=== Maintenance started ==='
    foreach ($id in $ids) { Run-MaintenanceItem $id }
    Write-Log '=== Maintenance finished ==='
    [void][System.Windows.Forms.MessageBox]::Show('Cleanup finished.', 'Finished', 'OK', 'Information')
})
$btnMaintRestore.add_Click({ Write-Log '--- Restore maintenance ---'; Restore-Maintenance; [void][System.Windows.Forms.MessageBox]::Show('Maintenance settings restored.', 'Finished', 'OK', 'Information') })
$btnMaintReport.add_Click({ Write-Log '--- Maintenance report ---'; Review-Maintenance })

$btnRepairRun.add_Click({
    $ids = @($script:repairChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    if ($ids.Count -eq 0) { [void][System.Windows.Forms.MessageBox]::Show('Tick at least one repair tool.', 'Nothing selected', 'OK', 'Warning'); return }
    $warn = $ids -contains 'chkdsk'
    if ($warn -and [System.Windows.Forms.MessageBox]::Show('chkdsk will run at the next restart. Continue?', 'Confirm', 'YesNo', 'Warning') -eq 'No') { return }
    Write-Log '=== System repair started (this can take a while) ==='
    foreach ($id in $ids) { Run-RepairItem $id }
    Write-Log '=== System repair finished ==='
    [void][System.Windows.Forms.MessageBox]::Show('Repair finished.', 'Finished', 'OK', 'Information')
})

Write-Log 'Ready. Pick items on the tabs, then Apply. Restore ALL returns everything to defaults.'
Write-Log ("Backups: " + $wsDir + "  and  " + $secDir)

if ($SmokeTest) {
    $marker = Join-Path $env:TEMP 'so_smoke.txt'
    New-Item -ItemType Directory -Path (Split-Path $marker) -Force | Out-Null
    Set-Content -Path $marker -Value 'SmokeTest bound = TRUE'
    $cb = [System.Threading.TimerCallback]{ param($state)
        try { $script:smokeTimer.Dispose() } catch { }
        try { $form.Invoke([System.Action]{ $form.Close() }) } catch { }
    }
    $script:smokeTimer = New-Object System.Threading.Timer($cb, $null, 3000, -1)
}

[void]$form.ShowDialog()
if ($SmokeTest) { Write-Output 'SMOKE OK' }
