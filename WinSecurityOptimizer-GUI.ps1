<#
.SYNOPSIS
  Windows Security Optimizer - GUI edition. Check the hardening items you want,
  apply them, restore, or run a full security review - all from a window.
  Every change is backed up to %ProgramData%\WinSecOpt for one-click restore.

.DESCRIPTION
  Hardening items:
   1. Defender cloud-delivered protection + block at first sight
   2. Firewall: block all inbound by default on all profiles
   3. Daily Defender quick scan at 03:00
   4. Auto-lock the screen after 10 minutes idle
   5. Harden Edge + Chrome browsers (safe browsing, block bad downloads, strict isolation)
   6. Enable System Restore + weekly restore points

.EXAMPLE
  WinSecurityOptimizer-GUI.exe             # normal GUI run
  WinSecurityOptimizer-GUI.exe -SmokeTest  # dev: open form 2s, then close
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
$secDir     = "$env:ProgramData\WinSecOpt"
$backupFile = Join-Path $secDir "backup.json"
$logFile    = Join-Path $secDir "harden.log"
$reviewFile = Join-Path $secDir "security-review.txt"

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin) -and -not $NoElevate) {
    [void][System.Windows.Forms.MessageBox]::Show(
        "Windows Security Optimizer needs administrator rights.`n`nClick OK to restart with elevation.",
        "Admin required", 'OK', 'Information')
    $me = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($me) -or -not (Test-Path $me)) {
        $me = [Diagnostics.Process]::GetCurrentProcess().Path
    }
    Start-Process -FilePath $me -Verb RunAs
    exit
}

# ---------------- UI ----------------
$script:logBox = $null
$script:checks = [System.Collections.ArrayList]@()

function Write-Log {
    param([string]$msg)
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    try { New-Item -ItemType Directory -Path $secDir -Force | Out-Null; Add-Content -Path $logFile -Value $line -ErrorAction Stop } catch { }
    if ($script:logBox) {
        $script:logBox.AppendText($line + "`r`n")
        [System.Windows.Forms.Application]::DoEvents()
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Windows Security Optimizer'
$form.ClientSize = New-Object System.Drawing.Size(650, 466)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$grp = New-Object System.Windows.Forms.GroupBox
$grp.Text = 'Hardening items (tick what to apply)'
$grp.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$grp.Location = New-Object System.Drawing.Point(10, 8)
$grp.Size = New-Object System.Drawing.Size(630, 190)

$items = @(
    @{ id='cloud';    text='1. Defender cloud protection (block at first sight)' },
    @{ id='firewall'; text='2. Firewall: block all unsolicited inbound by default' },
    @{ id='scan';     text='3. Daily Defender quick scan at 03:00' },
    @{ id='lock';     text='4. Auto-lock the screen after 10 minutes idle' },
    @{ id='browsers'; text='5. Harden Edge + Chrome (safe browsing, block bad downloads)' },
    @{ id='restore';  text='6. Enable System Restore + weekly restore points' }
)
$y = 30
foreach ($it in $items) {
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $it.text
    $cb.AutoSize = $true
    $cb.Checked = $true
    $cb.Tag = $it.id
    $cb.Location = New-Object System.Drawing.Point(15, $y)
    [void]$script:checks.Add($cb)
    $grp.Controls.Add($cb)
    $y += 26
}
$form.Controls.Add($grp)

$btnApply = New-Object System.Windows.Forms.Button
$btnApply.Text = 'Apply checked'
$btnApply.Size = New-Object System.Drawing.Size(110, 30)
$btnApply.Location = New-Object System.Drawing.Point(10, 206)

$btnRestore = New-Object System.Windows.Forms.Button
$btnRestore.Text = 'Restore'
$btnRestore.Size = New-Object System.Drawing.Size(110, 30)
$btnRestore.Location = New-Object System.Drawing.Point(128, 206)

$btnReview = New-Object System.Windows.Forms.Button
$btnReview.Text = 'Security review'
$btnReview.Size = New-Object System.Drawing.Size(120, 30)
$btnReview.Location = New-Object System.Drawing.Point(246, 206)

$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = 'Log:'
$lblLog.Location = New-Object System.Drawing.Point(10, 244)

$script:logBox = New-Object System.Windows.Forms.TextBox
$script:logBox.Multiline = $true
$script:logBox.ReadOnly = $true
$script:logBox.ScrollBars = 'Vertical'
$script:logBox.BackColor = [System.Drawing.Color]::FromArgb(32,32,32)
$script:logBox.ForeColor = [System.Drawing.Color]::White
$script:logBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$script:logBox.Location = New-Object System.Drawing.Point(10, 264)
$script:logBox.Size = New-Object System.Drawing.Size(630, 192)

$form.Controls.Add($btnApply)
$form.Controls.Add($btnRestore)
$form.Controls.Add($btnReview)
$form.Controls.Add($lblLog)
$form.Controls.Add($script:logBox)

# ---------------- helpers ----------------
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

function Get-MpSetting { try { return (Get-MpPreference -ErrorAction Stop) } catch { return $null } }

function Apply-CloudProtection {
    $mp = Get-MpSetting
    if (-not $mp) { Write-Log "SKIP cloud protection: Defender preferences unavailable."; return }
    if ($mp.MAPS -eq 2 -and $mp.SubmitSamplesConsent -eq 1 -and $mp.CloudBlockLevel -eq 2) {
        Write-Log "SKIP cloud protection: already hardened."; return
    }
    Save-BackupEntry 'cloud' (@{ MAPS = $mp.MAPS; SubmitSamplesConsent = $mp.SubmitSamplesConsent; CloudBlockLevel = $mp.CloudBlockLevel } | ConvertTo-Json -Compress)
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
                $old[$p] = @{ DefaultInboundAction = "$($pf.DefaultInboundAction)"; Enabled = $pf.Enabled }
            }
            Save-BackupEntry 'firewall' ($old | ConvertTo-Json -Compress)
            $changed = $true
        }
        Set-NetFirewallProfile -Name $profile -DefaultInboundAction Block -Enabled True -ErrorAction Stop
    }
    if ($changed) { Write-Log "ENABLED: firewall blocks all inbound by default." }
    else { Write-Log "SKIP firewall: all profiles already Block + enabled." }
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
    Save-BackupEntry 'lock' (@{ Active = "$oldActive"; Secure = "$oldSecure"; Timeout = "$oldTimeout" } | ConvertTo-Json -Compress)
    Set-ItemProperty $d -Name ScreenSaveActive -Value '1'
    Set-ItemProperty $d -Name ScreenSaverIsSecure -Value '1'
    Set-ItemProperty $d -Name ScreenSaveTimeOut -Value '600'
    Write-Log "ENABLED: auto-lock after 10 min idle."
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
Write-Log "ENABLED: browser hardening for Edge + Chrome."
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

function Apply-Item {
    param([string]$id)
    switch ($id) {
        'cloud'    { Apply-CloudProtection }
        'firewall' { Apply-FirewallBlock }
        'scan'     { Apply-ScanSchedule }
        'lock'     { Apply-AutoLock }
        'browsers' { Apply-BrowserHardening }
        'restore'  { Apply-SystemRestore }
    }
}

function Invoke-Restore {
    $rows = @(Get-Backup)
    if ($rows.Count -eq 0) { Write-Log "No backup found - nothing to restore."; return }
    Write-Log "=== Restore started ==="
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
                        if ($o.$p) { Set-NetFirewallProfile -Name $p -DefaultInboundAction $o.$p.DefaultInboundAction -Enabled $o.$p.Enabled }
                    }
                    Write-Log "RESTORED: firewall settings"
                }
                'scan' { Set-MpPreference -ScanScheduleQuickScanTime $row.Value; Write-Log "RESTORED: scan schedule" }
                'lock' {
                    $o = $row.Value | ConvertFrom-Json
                    $d = 'HKCU:\Control Panel\Desktop'
                    if ($null -ne $o.Active)  { Set-ItemProperty $d -Name ScreenSaveActive -Value $o.Active }
                    if ($null -ne $o.Secure)  { Set-ItemProperty $d -Name ScreenSaverIsSecure -Value $o.Secure }
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
                    $taskName = 'WeeklySystemRestorePoint'
                    try { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue } catch { }
                    $sysRestoreKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
                    if ($null -ne $o.Frequency -and $o.Frequency -ne '') {
                        Set-ItemProperty $sysRestoreKey -Name SystemRestorePointCreationFrequency -Value ([int]$o.Frequency) -Type DWord -ErrorAction SilentlyContinue
                    } else {
                        Remove-ItemProperty $sysRestoreKey -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue
                    }
                    Write-Log "RESTORED: weekly restore task + frequency. Protection left ENABLED (safer)."
                }
            }
        } catch {
            Write-Log "ERROR restoring $($row.Name): $($_.Exception.Message)"
        }
    }
    Remove-Item $backupFile -Force -ErrorAction SilentlyContinue
    Write-Log "=== Restore finished ==="
}

function Invoke-Review {
    $sb = New-Object System.Text.StringBuilder
    function Add-RevLine { param([string]$line) [void]$sb.AppendLine($line); Write-Log $line }
    function Get-RevVal { param($v, [string]$fb = 'n/a') if ($null -eq $v) { return $fb } return $v }

    Add-RevLine "=== Windows Security Review - $env:COMPUTERNAME ==="
    $st = Get-MpComputerStatus
    $mp = Get-MpSetting
    Add-RevLine ("  Real-time protection : " + (Get-RevVal $st.RealTimeProtectionEnabled))
    Add-RevLine ("  Tamper protection    : " + (Get-RevVal $st.IsTamperProtected))
    Add-RevLine ("  Signatures age (days): " + (Get-RevVal ([math]::Round(((Get-Date) - $st.AntivirusSignatureLastUpdated).TotalDays, 1))))
    Add-RevLine ("  Cloud protection MAPS: " + (Get-RevVal $mp.MAPS) + "  (2 = advanced, recommended)")
    Add-RevLine ("  Cloud block level    : " + (Get-RevVal $mp.CloudBlockLevel) + "  (2+ = recommended)")
    Add-RevLine ("  Exclusions count     : " + (Get-RevVal (@($st.ExclusionPath).Count + @($st.ExclusionProcess).Count + @($st.ExclusionExtension).Count)))
    Add-RevLine ""
    foreach ($profile in @('Domain','Private','Public')) {
        $f = Get-NetFirewallProfile -Name $profile
        Add-RevLine ("  Firewall {0}: enabled={1} defaultInbound={2}" -f $profile, $f.Enabled, $f.DefaultInboundAction)
    }
    Add-RevLine ""
    $rdp = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -ErrorAction SilentlyContinue).fDenyTSConnections
    Add-RevLine ("  Remote Desktop      : " + $(if ($rdp -eq 0) { 'ENABLED (consider disabling)' } else { 'disabled (good)' }))
    Add-RevLine ("  SMBv1               : " + (Get-RevVal (Get-SmbServerConfiguration).EnableSMB1Protocol) + "  (False = good)")
    $latest = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1
    Add-RevLine ("  Latest update       : " + $(if ($latest) { $latest.HotFixID + " (" + $latest.InstalledOn.ToString('yyyy-MM-dd') + ")" } else { 'n/a' }))
    $pending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
    Add-RevLine ("  Pending reboot      : " + $pending)
    $q = $mp.ScanScheduleQuickScanTime
    $qhour = if ($q -is [System.TimeSpan]) { $q.Hours } elseif ($null -ne $q) { $q } else { 'n/a' }
    Add-RevLine ("  Quick scan hour     : " + $qhour + " (24h)")
    $secure = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name ScreenSaverIsSecure -ErrorAction SilentlyContinue).ScreenSaverIsSecure
    $timeout = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name ScreenSaveTimeOut -ErrorAction SilentlyContinue).ScreenSaveTimeOut
    Add-RevLine ("  Screen locks on idle: " + $(if ($secure -eq '1') { "yes, after $([math]::Round($timeout/60)) min" } else { 'no (harden item 4)' }))
    Add-RevLine ""
    $edgeDl = (Get-ItemProperty $edgePolicies -Name DownloadRestrictions -ErrorAction SilentlyContinue).DownloadRestrictions
    $chromeDl = (Get-ItemProperty $chromePolicies -Name DownloadRestrictions -ErrorAction SilentlyContinue).DownloadRestrictions
Add-RevLine ("  Browser hardening   : Edge=" + $(if ($edgeDl -eq 2) { 'OK' } else { 'off' }) + "  Chrome=" + $(if ($chromeDl -eq 2) { 'OK' } else { 'off' }) + "  (item 5)")
    $rps = @(Get-ComputerRestorePoint -ErrorAction SilentlyContinue)
    if ($rps.Count -eq 0) { Add-RevLine ("  Restore points     : none found (protection likely OFF) - enable via item 6") }
    else {
        $last = $rps | Sort-Object CreationTime -Descending | Select-Object -First 1
        Add-RevLine ("  Restore points     : " + $rps.Count + "  latest: " + $(if ($last) { $last.CreationTime.ToString('yyyy-MM-dd HH:mm') } else { 'n/a' }))
    }
    $weekTask = Get-ScheduledTask -TaskName 'WeeklySystemRestorePoint' -ErrorAction SilentlyContinue
    Add-RevLine ("  Weekly point task  : " + $(if ($weekTask) { 'scheduled (item 6)' } else { 'not scheduled' }))
    if ($st.RealTimeProtectionEnabled -and $mp.MAPS -eq 2) { Add-RevLine "Recommendation: Defender OK." } else { Add-RevLine "Recommendation: run Apply to enable cloud protection." }
    New-Item -ItemType Directory -Path $secDir -Force | Out-Null
    $sb.ToString() | Set-Content -Path $reviewFile -Encoding UTF8
    Write-Log ("Report saved to: " + $reviewFile)
}

# ---------------- handlers ----------------
$btnApply.add_Click({
    $ids = @($script:checks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    if ($ids.Count -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show('Tick at least one hardening item.', 'Nothing selected', 'OK', 'Warning')
        return
    }
    Write-Log '=== Security Optimizer started ==='
    foreach ($id in $ids) { Apply-Item $id }
    Write-Log '=== Security Optimizer finished ==='
    [void][System.Windows.Forms.MessageBox]::Show('Hardening applied. A reboot is recommended.', 'Finished', 'OK', 'Information')
})

$btnRestore.add_Click({
    Invoke-Restore
    [void][System.Windows.Forms.MessageBox]::Show('Restore complete.', 'Finished', 'OK', 'Information')
})

$btnReview.add_Click({
    Invoke-Review
})

Write-Log 'Ready. Tick hardening items and click Apply checked.'
Write-Log ("Backup folder: " + $secDir)

if ($SmokeTest) {
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 2000
    $timer.add_Tick({ $form.Close() })
    $timer.Start()
}

[void]$form.ShowDialog()


