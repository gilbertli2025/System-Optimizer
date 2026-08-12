<#
.SYNOPSIS
  Windows Security Optimizer - hardens a Windows 10/11 PC against malware:
  enables Defender cloud protection, blocks all unsolicited inbound firewall
  traffic, schedules daily Defender quick scans and auto-locks the screen.
  Every change is backed up and can be fully restored.

.DESCRIPTION
  Apply-Harden  : applies the safe hardening items below.
  Restore       : reverts every change from the backup.
  Review        : read-only security audit of this PC (report saved to
                  %ProgramData%\WinSecOpt\security-review.txt).

  Hardening items:
   1. Defender cloud-delivered protection + block at first sight
   2. Firewall: block all inbound by default on all profiles
   3. Daily Defender quick scan at 03:00
   4. Auto-lock the screen after 10 minutes idle
   5. Harden Edge + Chrome browsers (safe browsing, block bad downloads, strict isolation)
   6. Enable System Restore + weekly restore points

.EXAMPLE
  WinSecurityOptimizer.exe                # interactive menu
  WinSecurityOptimizer.exe -Harden        # apply hardening
  WinSecurityOptimizer.exe -Restore       # undo hardening
  WinSecurityOptimizer.exe -Review        # security audit report
#>
[CmdletBinding()]
param(
    [switch]$Harden,
    [switch]$Restore,
    [switch]$Review
)

$ErrorActionPreference = 'Continue'
$secDir     = "$env:ProgramData\WinSecOpt"
$backupFile = Join-Path $secDir "backup.json"
$logFile    = Join-Path $secDir "harden.log"
$reviewFile = Join-Path $secDir "security-review.txt"

function Write-Log {
    param([string]$msg)
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    try { New-Item -ItemType Directory -Path $secDir -Force | Out-Null; Add-Content -Path $logFile -Value $line -ErrorAction Stop } catch { }
    Write-Host $line
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
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

# ---------------- backup ----------------
function Get-Backup {
    if (Test-Path $backupFile) {
        try { return @(Get-Content $backupFile -Raw | ConvertFrom-Json) } catch { return @() }
    }
    return @()
}

function Save-BackupEntry {
    param([string]$name, [string]$value)
    $rows = @(Get-Backup | Where-Object { $_.Name -ne $name })
    $rows += [PSCustomObject]@{ Name = $name; Value = $value }
    New-Item -ItemType Directory -Path $secDir -Force | Out-Null
    $rows | ConvertTo-Json | Set-Content -Path $backupFile -Encoding UTF8
}

# ---------------- hardening item helpers ----------------
function Get-MpSetting { try { return (Get-MpPreference -ErrorAction Stop) } catch { return $null } }

function Apply-CloudProtection {
    $mp = Get-MpSetting
    if (-not $mp) { Write-Log "SKIP cloud protection: Defender preferences unavailable."; return }
    if ($mp.MAPS -eq 2 -and $mp.SubmitSamplesConsent -eq 1 -and $mp.CloudBlockLevel -eq 2) {
        Write-Log "SKIP cloud protection: already hardened (MAPS=2, consent=1, block=2)."
        return
    }
    Save-BackupEntry 'cloud' (@{ MAPS = $mp.MAPS; SubmitSamplesConsent = $mp.SubmitSamplesConsent; CloudBlockLevel = $mp.CloudBlockLevel } | ConvertTo-Json -Compress)
    Set-MpPreference -MAPS 2 -SubmitSamplesConsent 1 -CloudBlockLevel 2 -ErrorAction Stop
    Write-Log "ENABLED: Defender cloud protection (MAPS=2, submit safe samples, block level 2)."
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
                $old[$p] = @{ DefaultInboundAction = "$($pf.DefaultInboundAction)"; Enabled = $pf.Enabled }
            }
            Save-BackupEntry 'firewall' ($old | ConvertTo-Json -Compress)
            $changed = $true
        }
        Set-NetFirewallProfile -Name $profile -DefaultInboundAction Block -Enabled True -ErrorAction Stop
    }
    if ($changed) { Write-Log "ENABLED: firewall blocks all inbound by default on Domain/Private/Public." }
    else { Write-Log "SKIP firewall: all profiles already Block + enabled." }
}

function Apply-ScanSchedule {
    $mp = Get-MpSetting
    if (-not $mp) { Write-Log "SKIP scan schedule: Defender preferences unavailable."; return }
    if ($mp.ScanScheduleQuickScanTime -eq 3) { Write-Log "SKIP scan schedule: already set to 03:00."; return }
    Save-BackupEntry 'scan' ("$($mp.ScanScheduleQuickScanTime)")
    Set-MpPreference -ScanScheduleQuickScanTime 3 -ErrorAction Stop
    Write-Log "ENABLED: daily Defender quick scan scheduled at 03:00."
}

function Apply-AutoLock {
    $d = 'HKCU:\Control Panel\Desktop'
    $oldActive = (Get-ItemProperty $d -Name ScreenSaveActive -ErrorAction SilentlyContinue).ScreenSaveActive
    $oldSecure = (Get-ItemProperty $d -Name ScreenSaverIsSecure -ErrorAction SilentlyContinue).ScreenSaverIsSecure
    $oldTimeout = (Get-ItemProperty $d -Name ScreenSaveTimeOut -ErrorAction SilentlyContinue).ScreenSaveTimeOut
    if ($oldSecure -eq '1') { Write-Log "SKIP auto-lock: screen already locks after idle."; return }
    Save-BackupEntry 'lock' (@{ Active = "$oldActive"; Secure = "$oldSecure"; Timeout = "$oldTimeout" } | ConvertTo-Json -Compress)
    Set-ItemProperty $d -Name ScreenSaveActive -Value '1'
    Set-ItemProperty $d -Name ScreenSaverIsSecure -Value '1'
    Set-ItemProperty $d -Name ScreenSaveTimeOut -Value '600'
    Write-Log "ENABLED: screen auto-locks after 10 minutes idle."
}

$edgePolicies   = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
$chromePolicies = 'HKLM:\SOFTWARE\Policies\Google\Chrome'

function Apply-BrowserHardening {
    $edge = @{
        'SmartScreenEnabled'                = 1
        'SmartScreenForTrustedDownloadsEnabled' = 1
        'SafeBrowsingEnabled'               = 1
        'DownloadRestrictions'              = 2
        'BlockThirdPartyCookies'            = 1
        'DefaultPopupsSetting'              = 2
        'SitePerProcess'                    = 1
        'DefaultWebUsbSetting'              = 2
        'DefaultWebSerialSetting'           = 2
        'AutofillCreditCardEnabled'         = 0
    }
    $chrome = @{
        'SafeBrowsingProtectionLevel'       = 2
        'DownloadRestrictions'              = 2
        'BlockThirdPartyCookies'            = 1
        'DefaultPopupsSetting'              = 2
        'SitePerProcess'                    = 1
        'DefaultWebUsbSetting'              = 2
        'DefaultWebSerialSetting'           = 2
        'AutofillCreditCardEnabled'         = 0
    }

    $already = ((Get-ItemProperty $edgePolicies -Name DownloadRestrictions -ErrorAction SilentlyContinue).DownloadRestrictions -eq 2) -and
               ((Get-ItemProperty $chromePolicies -Name DownloadRestrictions -ErrorAction SilentlyContinue).DownloadRestrictions -eq 2)
    if ($already) { Write-Log "SKIP browsers: Edge + Chrome already hardened."; return }

    $old = @{ edge = @{}; chrome = @{} }
    foreach ($b in @('edge','chrome')) {
        $key = if ($b -eq 'edge') { $edgePolicies } else { $chromePolicies }
        $pol = if ($b -eq 'edge') { $edge } else { $chrome }
        foreach ($pn in $pol.Keys) {
            $cur = (Get-ItemProperty $key -Name $pn -ErrorAction SilentlyContinue).$pn
            $old[$b][$pn] = $(if ($null -eq $cur) { 'MISSING' } else { $cur })
        }
    }
    Save-BackupEntry 'browsers' ($old | ConvertTo-Json -Compress)

    foreach ($b in @('edge','chrome')) {
        $key = if ($b -eq 'edge') { $edgePolicies } else { $chromePolicies }
        $pol = if ($b -eq 'edge') { $edge } else { $chrome }
        New-Item -ItemType Directory -Path $key -Force | Out-Null
        foreach ($pn in $pol.Keys) { Set-ItemProperty -Path $key -Name $pn -Value $pol[$pn] -Type DWord -ErrorAction Stop }
    }
Write-Log "ENABLED: browser hardening for Edge + Chrome (SmartScreen/SafeBrowsing, block dangerous downloads, 3rd-party cookies blocked, strict site isolation, WebUSB/WebSerial blocked, no credit-card autofill)."
}

function Apply-SystemRestore {
    $drives = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object { $_.DeviceID })
    if ($drives.Count -eq 0) { Write-Log "SKIP restore points: no fixed drive found."; return }
    $sysRestoreKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $freqNow = (Get-ItemProperty $sysRestoreKey -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency

    Save-BackupEntry 'restore' (@{ Drives = ($drives -join ','); Frequency = "$freqNow" } | ConvertTo-Json -Compress)

    foreach ($d in $drives) {
        try { Enable-ComputerRestore -Drive "$d\" -ErrorAction Stop; Write-Log "ENABLED: system protection on $d." } catch { Write-Log "WARN enable protection $d`: $($_.Exception.Message)" }
    }
    try { Set-ItemProperty $sysRestoreKey -Name SystemRestorePointCreationFrequency -Value 0 -Type DWord -ErrorAction Stop } catch { Write-Log "WARN set restore frequency: $($_.Exception.Message)" }

    $taskName = 'WeeklySystemRestorePoint'
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -Command "Checkpoint-Computer -Description ''Weekly Restore Point'' -RestorePointType MODIFY_SETTINGS"'
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 4am
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    try {
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force -ErrorAction Stop | Out-Null
        Write-Log "ENABLED: weekly restore point task ($taskName) every Sunday 04:00."
    } catch { Write-Log "WARN schedule weekly task: $($_.Exception.Message)" }

    try { Checkpoint-Computer -Description 'Security Optimizer baseline' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop | Out-Null; Write-Log "Created a restore point now." } catch { Write-Log "WARN checkpoint now: $($_.Exception.Message)" }
}

# ---------------- harden / restore ----------------
function Invoke-Harden {
    New-Item -ItemType Directory -Path $secDir -Force | Out-Null
    Write-Log "=== Security Optimizer started ==="
    Apply-CloudProtection
    Apply-FirewallBlock
    Apply-ScanSchedule
    Apply-AutoLock
Apply-BrowserHardening
    Apply-SystemRestore
    Write-Log "=== Security Optimizer finished ==="
    Write-Host "`nDone. Backup at $backupFile. To undo, run with -Restore." -ForegroundColor Green
}

function Invoke-Restore {
    $rows = @(Get-Backup)
    if ($rows.Count -eq 0) { Write-Host "No backup found - nothing to restore."; return }
    New-Item -ItemType Directory -Path $secDir -Force | Out-Null
    Write-Log "=== Security Optimizer restore started ==="
    foreach ($row in $rows) {
        try {
            switch ($row.Name) {
                'cloud' {
                    $o = $row.Value | ConvertFrom-Json
                    if ($null -ne $o.MAPS)    { Set-MpPreference -MAPS $o.MAPS }
                    if ($null -ne $o.SubmitSamplesConsent) { Set-MpPreference -SubmitSamplesConsent $o.SubmitSamplesConsent }
                    if ($null -ne $o.CloudBlockLevel) { Set-MpPreference -CloudBlockLevel $o.CloudBlockLevel }
                    Write-Log "RESTORED: cloud protection"
                }
                'firewall' {
                    $o = $row.Value | ConvertFrom-Json
                    foreach ($p in @('Domain','Private','Public')) {
                        if ($o.$p) {
                            Set-NetFirewallProfile -Name $p -DefaultInboundAction $o.$p.DefaultInboundAction -Enabled $o.$p.Enabled
                        }
                    }
                    Write-Log "RESTORED: firewall settings"
                }
                'scan' { Set-MpPreference -ScanScheduleQuickScanTime $row.Value; Write-Log "RESTORED: scan schedule" }
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
                    $taskName = 'WeeklySystemRestorePoint'
                    try { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue } catch { }
                    $sysRestoreKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
                    if ($null -ne $o.Frequency -and $o.Frequency -ne '') {
                        Set-ItemProperty $sysRestoreKey -Name SystemRestorePointCreationFrequency -Value ([int]$o.Frequency) -Type DWord -ErrorAction SilentlyContinue
                    } else {
                        Remove-ItemProperty $sysRestoreKey -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue
                    }
                    Write-Log "RESTORED: weekly restore task + frequency. Protection left ENABLED (safer); disable it in System Properties if you really want it off."
                }
                'lock' {
                    $o = $row.Value | ConvertFrom-Json
                    $d = 'HKCU:\Control Panel\Desktop'
                    if ($null -ne $o.Active)  { Set-ItemProperty $d -Name ScreenSaveActive -Value $o.Active }
                    if ($null -ne $o.Secure)  { Set-ItemProperty $d -Name ScreenSaverIsSecure -Value $o.Secure }
                    if ($null -ne $o.Timeout) { Set-ItemProperty $d -Name ScreenSaveTimeOut -Value $o.Timeout }
                    Write-Log "RESTORED: auto-lock"
                }
            }
        } catch {
            Write-Log "ERROR restoring $($row.Name): $($_.Exception.Message)"
        }
    }
    Remove-Item $backupFile -Force -ErrorAction SilentlyContinue
    Write-Log "=== Security Optimizer restore finished ==="
    Write-Host "`nRestore complete. Backup cleared." -ForegroundColor Green
}

# ---------------- review ----------------
function Get-Val {
    param([scriptblock]$expr, [string]$fallback = 'n/a')
    try { $v = & $expr; if ($null -eq $v) { return $fallback }; return $v } catch { return $fallback }
}

function Invoke-Review {
    $sb = New-Object System.Text.StringBuilder
    function Add-RevLine { param([string]$line) [void]$sb.AppendLine($line); Write-Host $line }

    Add-RevLine "=== Windows Security Review - $env:COMPUTERNAME ==="
    Add-RevLine ("Date: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    Add-RevLine ""
    Add-RevLine "-- Windows Defender --"
    $st = Get-MpComputerStatus
    Add-RevLine ("  Real-time protection : " + $(Get-Val { $st.RealTimeProtectionEnabled }))
    Add-RevLine ("  Antivirus enabled    : " + $(Get-Val { $st.AntivirusEnabled }))
    Add-RevLine ("  Tamper protection    : " + $(Get-Val { $st.IsTamperProtected }))
    $sigAge = Get-Val { [math]::Round(((Get-Date) - $st.AntivirusSignatureLastUpdated).TotalDays, 1) }
    Add-RevLine ("  Signatures age (days): " + $sigAge)
    $mp = Get-MpSetting
    Add-RevLine ("  Cloud protection MAPS: " + $(Get-Val { $mp.MAPS }) + "   (2 = advanced, recommended)")
    Add-RevLine ("  Cloud block level    : " + $(Get-Val { $mp.CloudBlockLevel }) + "   (2+ = moderate/high, recommended)")
    Add-RevLine ("  Exclusions count     : " + $(Get-Val { @($st.ExclusionPath).Count + @($st.ExclusionProcess).Count + @($st.ExclusionExtension).Count }))

    Add-RevLine ""
    Add-RevLine "-- Firewall --"
    foreach ($profile in @('Domain','Private','Public')) {
        $f = Get-NetFirewallProfile -Name $profile
        Add-RevLine ("  {0,-8} enabled={1}  defaultInbound={2}" -f $profile, $f.Enabled, $f.DefaultInboundAction)
    }

    Add-RevLine ""
    Add-RevLine "-- Remote access & sharing --"
    $rdp = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -ErrorAction SilentlyContinue).fDenyTSConnections
    Add-RevLine ("  Remote Desktop      : " + $(if ($rdp -eq 0) { 'ENABLED (consider disabling)' } else { 'disabled (good)' }))
    Add-RevLine ("  SMBv1               : " + $(Get-Val { (Get-SmbServerConfiguration).EnableSMB1Protocol } 'n/a') + "   (False = good)")
    $shares = @(Get-SmbShare | Where-Object { $_.Name -notmatch '^\w+\$$' })
    Add-RevLine ("  User file shares    : " + $(if ($shares.Count -eq 0) { 'none (good)' } else { ($shares.Name -join ', ') }))

    Add-RevLine ""
    Add-RevLine "-- Accounts & UAC --"
    $admins = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    $enabledUsers = @(Get-LocalUser | Where-Object Enabled)
    foreach ($u in $enabledUsers) { $isAdmin = $admins -contains ($env:COMPUTERNAME + '\' + $u.Name); Add-RevLine ("  User '{0}' : {1}" -f $u.Name, $(if ($isAdmin) { 'ADMINISTRATOR' } else { 'standard' })) }
    $lua = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA -ErrorAction SilentlyContinue).EnableLUA
    Add-RevLine ("  UAC enabled         : " + $(if ($lua -eq 1) { 'yes (good)' } else { 'NO - not recommended' }))

    Add-RevLine ""
    Add-RevLine "-- Updates & schedule --"
    $latest = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1
    Add-RevLine ("  Latest update       : " + $(if ($latest) { $latest.HotFixID + " (" + $latest.InstalledOn.ToString('yyyy-MM-dd') + ")" } else { 'n/a' }))
    $pending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
    Add-RevLine ("  Pending reboot      : " + $pending)
    $q = $mp.ScanScheduleQuickScanTime
    $qhour = if ($q -is [System.TimeSpan]) { $q.Hours } elseif ($null -ne $q) { $q } else { 'n/a' }
    Add-RevLine ("  Defender quick scan : " + $qhour + " (hour of day, 24h)")

    Add-RevLine ""
    Add-RevLine "-- Auto-lock --"
    $secure = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name ScreenSaverIsSecure -ErrorAction SilentlyContinue).ScreenSaverIsSecure
    $timeout = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name ScreenSaveTimeOut -ErrorAction SilentlyContinue).ScreenSaveTimeOut
    Add-RevLine ("  Screen locks on idle: " + $(if ($secure -eq '1') { "yes, after $([math]::Round($timeout/60)) min" } else { 'no - set auto-lock (harden item 4)' }))

    Add-RevLine ""
    Add-RevLine "-- BitLocker --"
    $bl = Get-BitLockerVolume -MountPoint 'C:' -ErrorAction SilentlyContinue
    if ($bl) { Add-RevLine ("  C: protection        : " + $bl.ProtectionStatus + "   (On = drive encrypted)") } else { Add-RevLine "  C: protection        : n/a (requires admin to query)" }

    Add-RevLine ""
    Add-RevLine "-- Browsers (policies) --"
    foreach ($b in @(@('Edge', $edgePolicies), @('Chrome', $chromePolicies))) {
        $bname = $b[0]; $key = $b[1]
        $dl = (Get-ItemProperty $key -Name DownloadRestrictions -ErrorAction SilentlyContinue).DownloadRestrictions
        $cookies = (Get-ItemProperty $key -Name BlockThirdPartyCookies -ErrorAction SilentlyContinue).BlockThirdPartyCookies
        $sb2 = (Get-ItemProperty $key -Name SafeBrowsingEnabled -ErrorAction SilentlyContinue).SafeBrowsingEnabled
        $sbl = (Get-ItemProperty $key -Name SafeBrowsingProtectionLevel -ErrorAction SilentlyContinue).SafeBrowsingProtectionLevel
        $smart = (Get-ItemProperty $key -Name SmartScreenEnabled -ErrorAction SilentlyContinue).SmartScreenEnabled
        Add-RevLine ("  {0,-7} blockDownload={1}  block3rdPartyCookies={2}  safeBrowsing/SmartScreen={3}" -f $bname, $(if ($dl -eq 2) { 'yes' } else { 'no' }), $(if ($cookies -eq 1) { 'yes' } else { 'no' }), $(if ($bname -eq 'Edge') { $smart } else { $sbl }))
    }

Add-RevLine ""
    Add-RevLine "-- System Restore --"
    $rps = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue)
    if ($rps.Count -eq 0) {
        Add-RevLine "  Restore points     : none found (protection likely OFF) - enable via item 6"
    } else {
        $last = $rps | Sort-Object CreationTime -Descending | Select-Object -First 1
        Add-RevLine ("  Restore points     : " + $rps.Count)
        Add-RevLine ("  Latest point       : " + $(if ($last) { $last.CreationTime.ToString('yyyy-MM-dd HH:mm') } else { 'n/a' }))
    }
    $weekTask = Get-ScheduledTask -TaskName 'WeeklySystemRestorePoint' -ErrorAction SilentlyContinue
    Add-RevLine ("  Weekly point task  : " + $(if ($weekTask) { 'scheduled (item 6)' } else { 'not scheduled' }))

    Add-RevLine ""
    Add-RevLine "Recommendation summary:"
    if ($st.RealTimeProtectionEnabled -and $mp.MAPS -eq 2) { Add-RevLine "  - Defender real-time + cloud protection: OK" } else { Add-RevLine "  - Run Harden to enable cloud protection / confirm real-time." }
    $allBlocked = -not (Get-NetFirewallProfile | Where-Object { $_.DefaultInboundAction -ne 'Block' })
    if ($allBlocked) { Add-RevLine "  - Firewall inbound default: OK" } else { Add-RevLine "  - Run Harden to block unsolicited inbound traffic." }
    $edgeOK = (Get-ItemProperty $edgePolicies -Name DownloadRestrictions -ErrorAction SilentlyContinue).DownloadRestrictions -eq 2
    $chromeOK = (Get-ItemProperty $chromePolicies -Name DownloadRestrictions -ErrorAction SilentlyContinue).DownloadRestrictions -eq 2
    if ($edgeOK -and $chromeOK) { Add-RevLine "  - Browser hardening (Edge + Chrome): OK" } else { Add-RevLine "  - Run Harden to enable browser hardening (item 5)." }

    New-Item -ItemType Directory -Path $secDir -Force | Out-Null
    $sb.ToString() | Set-Content -Path $reviewFile -Encoding UTF8
    Write-Host ""
    Write-Host ("Report saved to: " + $reviewFile) -ForegroundColor Cyan
}

# ---------------- entry ----------------
if ($Harden) {
    if (-not (Test-Admin)) { Restart-Admin @('-Harden'); return }
    Invoke-Harden
    exit
}
if ($Restore) {
    if (-not (Test-Admin)) { Restart-Admin @('-Restore'); return }
    Invoke-Restore
    exit
}
if ($Review) { Invoke-Review; exit }

while ($true) {
    Write-Host ""
    Write-Host "=== Windows Security Optimizer ===" -ForegroundColor White
    Write-Host "   1) Apply hardening (recommended)"
    Write-Host "   2) Restore (undo hardening)"
    Write-Host "   3) Security review"
    Write-Host "   Q) Quit"
    $choice = Read-Host "Choose an option"
    switch ($choice.Trim().ToUpper()) {
        '1' { if (-not (Test-Admin)) { Restart-Admin @('-Harden') } else { Invoke-Harden }; Read-Host "`nPress Enter to continue..." }
        '2' { if (-not (Test-Admin)) { Restart-Admin @('-Restore') } else { Invoke-Restore }; Read-Host "`nPress Enter to continue..." }
        '3' { Invoke-Review; Read-Host "`nPress Enter to continue..." }
        'Q' { Write-Host "Bye."; exit }
        default { Write-Host "Invalid choice." }
    }
}


