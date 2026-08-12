<#
.SYNOPSIS
  Windows Services Optimizer - GUI edition. Windowed app that lets you pick
  which services to disable (checkboxes), optimize, restore, or verify - all
  from a simple form. Compiled to a standalone .exe (no console).

.DESCRIPTION
  Lists a SAFE set of services (recommended, pre-checked) and an OPTIONAL set
  that can affect a feature. Every change is backed up to
  %ProgramData%\WinServiceOpt so Restore can roll it all back. The form
  self-elevates (UAC) at startup.

.EXAMPLE
  WinServiceOptimizer-GUI.exe             # normal GUI run
  WinServiceOptimizer-GUI.exe -SmokeTest  # dev: open form 2s, then close
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
$backupDir    = "$env:ProgramData\WinServiceOpt"
$backupFile   = Join-Path $backupDir "services-backup.csv"
$snapshotFile = Join-Path $backupDir "all-services-snapshot.csv"
$logFile      = Join-Path $backupDir "optimize.log"

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

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin) -and -not $NoElevate) {
    [void][System.Windows.Forms.MessageBox]::Show(
        "Windows Services Optimizer needs administrator rights.`n`nClick OK to restart with elevation.",
        "Admin required", 'OK', 'Information')
    $me = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($me) -or -not (Test-Path $me)) {
        $me = [Diagnostics.Process]::GetCurrentProcess().Path
    }
    Start-Process -FilePath $me -Verb RunAs
    exit
}

# ---------------- UI ----------------
$script:allChecks = [System.Collections.ArrayList]@()
$script:logBox = $null

function Write-Log {
    param([string]$msg)
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    try { Add-Content -Path $logFile -Value $line -ErrorAction Stop } catch { }
    if ($script:logBox) {
        $script:logBox.AppendText($line + "`r`n")
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Get-CurrentStartType {
    param([string]$name)
    try { return (Get-Service -Name $name -ErrorAction Stop).StartType } catch { return '' }
}

function New-ServiceGroup {
    param([string]$title, [string[]]$names, [bool]$checked, [int]$x)
    $gb = New-Object System.Windows.Forms.GroupBox
    $gb.Text = $title
    $gb.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $gb.Location = New-Object System.Drawing.Point($x, 8)
    $gb.Size = New-Object System.Drawing.Size(385, 400)

    $fl = New-Object System.Windows.Forms.FlowLayoutPanel
    $fl.Location = New-Object System.Drawing.Point(10, 25)
    $fl.Size = New-Object System.Drawing.Size(365, 368)
    $fl.AutoScroll = $true
    $fl.WrapContents = $false
    $fl.FlowDirection = 'TopDown'

    foreach ($name in $names) {
        $cb = New-Object System.Windows.Forms.CheckBox
        $disp = (Get-Service -Name $name -ErrorAction SilentlyContinue).DisplayName
        $cb.Text = if ($disp) { "$name  ($disp)" } else { $name }
        $cb.Font = New-Object System.Drawing.Font('Consolas', 9)
        $cb.AutoSize = $true
        $cb.Checked = $checked
        $cb.Tag = $name
        [void]$script:allChecks.Add($cb)
        $fl.Controls.Add($cb)
    }
    $gb.Controls.Add($fl)
    return $gb
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Windows Services Optimizer'
$form.ClientSize = New-Object System.Drawing.Size(790, 600)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$form.Controls.Add((New-ServiceGroup 'SAFE services (recommended)' $safeServices $true 10))
$form.Controls.Add((New-ServiceGroup 'OPTIONAL services (affect features)' $optionalServices $false 410))

$btnOptimize = New-Object System.Windows.Forms.Button
$btnOptimize.Text = 'Optimize selected'
$btnOptimize.Size = New-Object System.Drawing.Size(120, 30)
$btnOptimize.Location = New-Object System.Drawing.Point(10, 416)

$btnRestore = New-Object System.Windows.Forms.Button
$btnRestore.Text = 'Restore'
$btnRestore.Size = New-Object System.Drawing.Size(100, 30)
$btnRestore.Location = New-Object System.Drawing.Point(138, 416)

$btnVerify = New-Object System.Windows.Forms.Button
$btnVerify.Text = 'Verify'
$btnVerify.Size = New-Object System.Drawing.Size(100, 30)
$btnVerify.Location = New-Object System.Drawing.Point(246, 416)

$btnDefaults = New-Object System.Windows.Forms.Button
$btnDefaults.Text = 'Safe defaults'
$btnDefaults.Size = New-Object System.Drawing.Size(100, 30)
$btnDefaults.Location = New-Object System.Drawing.Point(354, 416)

$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = 'Log:'
$lblLog.Location = New-Object System.Drawing.Point(10, 452)

$script:logBox = New-Object System.Windows.Forms.TextBox
$script:logBox.Multiline = $true
$script:logBox.ReadOnly = $true
$script:logBox.ScrollBars = 'Vertical'
$script:logBox.BackColor = [System.Drawing.Color]::FromArgb(32,32,32)
$script:logBox.ForeColor = [System.Drawing.Color]::White
$script:logBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$script:logBox.Location = New-Object System.Drawing.Point(10, 472)
$script:logBox.Size = New-Object System.Drawing.Size(770, 118)

$form.Controls.Add($btnOptimize)
$form.Controls.Add($btnRestore)
$form.Controls.Add($btnVerify)
$form.Controls.Add($btnDefaults)
$form.Controls.Add($lblLog)
$form.Controls.Add($script:logBox)

# ---------------- actions ----------------
function Get-Selected {
    $names = @()
    foreach ($cb in $script:allChecks) { if ($cb.Checked) { $names += $cb.Tag } }
    return $names
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
        Write-Log "No backup found at $backupFile - nothing to restore."
        return
    }
    $rows = @(Import-Csv $backupFile)
    if ($rows.Count -eq 0) { Write-Log "Backup is empty - nothing to restore."; return }
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
    Write-Log "Restore complete. Backup file kept at $backupFile."
}

function Invoke-Verify {
    $p = 0; $f = 0; $w = 0
    if (-not (Test-Path $backupDir)) { Write-Log "No backup folder found - optimizer has NOT been run."; return }
    $ran = $false
    if (Test-Path $logFile) {
        $log = Get-Content $logFile -ErrorAction SilentlyContinue
        if ($log -match "Optimizer started") { $ran = $true; Write-Log "[PASS] Optimization run detected in log." }
    } else { Write-Log "[FAIL] Log file not found."; $f++ }
    if (-not (Test-Path $backupFile)) { Write-Log "[FAIL] Backup file not found."; return }
    $rows = @(Import-Csv $backupFile -ErrorAction SilentlyContinue)
    if ($rows.Count -eq 0) { Write-Log "Backup empty - nothing to verify."; return }
    Write-Log "Services targeted: $($rows.Count)"
    foreach ($row in $rows) {
        $svc = Get-Service -Name $row.Name -ErrorAction SilentlyContinue
        if (-not $svc) { Write-Log "[WARN] $($row.Name) no longer exists."; $w++; continue }
        if ($svc.StartType -eq 'Disabled') { Write-Log "[PASS] $($row.Name) disabled."; $p++ }
        else { Write-Log "[FAIL] $($row.Name) expected Disabled, is $($svc.StartType)."; $f++ }
    }
    if (Test-Path $snapshotFile) {
        $snap = @(Import-Csv $snapshotFile -ErrorAction SilentlyContinue)
        foreach ($row in $snap) {
            if ($protected -notcontains $row.Name) { continue }
            $cur = Get-Service -Name $row.Name -ErrorAction SilentlyContinue
            if (-not $cur) { continue }
            $norm = switch ($row.StartMode) { 'Auto' { 'Automatic' } 'AutoStart' { 'Automatic' } default { $row.StartMode } }
            if ($norm -eq $cur.StartType) { Write-Log "[PASS] Protected $($row.Name) unchanged."; $p++ }
            else { Write-Log "[WARN] Protected $($row.Name) changed ($($row.StartMode) -> $($cur.StartType))."; $w++ }
        }
    }
    Write-Log "Summary: PASS=$p FAIL=$f WARN=$w"
    if ($f -gt 0) { Write-Log "RESULT: Issues found." } elseif (-not $ran) { Write-Log "RESULT: Run not confirmed." } else { Write-Log "RESULT: OK." }
}

# ---------------- handlers ----------------
$btnOptimize.add_Click({
    $names = @(Get-Selected)
    if ($names.Count -eq 0) {
        [void][System.Windows.Forms.MessageBox]::Show('Select at least one service.', 'Nothing selected', 'OK', 'Warning')
        return
    }
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    Write-Log '=== Windows Services Optimizer started ==='
    Backup-State
    Disable-Services $names
    Write-Log '=== Optimization finished ==='
    [void][System.Windows.Forms.MessageBox]::Show("Done. $($names.Count) selected services processed.`nReboot recommended.", 'Finished', 'OK', 'Information')
})

$btnRestore.add_Click({
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    Write-Log '=== Windows Services Optimizer started ==='
    Restore-Services
    Write-Log '=== Optimization finished ==='
    [void][System.Windows.Forms.MessageBox]::Show('Restore complete.', 'Finished', 'OK', 'Information')
})

$btnVerify.add_Click({
    Write-Log '--- Verification ---'
    Invoke-Verify
})

$btnDefaults.add_Click({
    foreach ($cb in $script:allChecks) {
        $cb.Checked = ($safeServices -contains $cb.Tag)
    }
})

Write-Log 'Ready. Pick services, then click Optimize selected.'
Write-Log ("Backup/log folder: " + $backupDir)

if ($SmokeTest) {
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 2000
    $timer.add_Tick({ $form.Close() })
    $timer.Start()
}

[void]$form.ShowDialog()
