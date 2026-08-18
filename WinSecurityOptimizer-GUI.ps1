<#
.SYNOPSIS
  Windows Security Optimizer - GUI edition (thin shim).

  Real logic lives in lib/*.ps1. This file is just the WinForms window.

.DESCRIPTION
  Has 6 of the 10 security items (the "safe six": Defender cloud, firewall,
  scan schedule, auto-lock, browsers, system restore). The other four
  (BitLocker, AutoRun, Account lockout, Office macros + WSH) are available
  in the unified SystemOptimizer GUI.
#>
[CmdletBinding()]
param(
    [switch]$SmokeTest,
    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Locate lib/ whether running from source or from an installed folder.
$ScriptRoot = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { (Get-Location).Path }
. (Join-Path $ScriptRoot 'lib\Common.ps1')
. (Join-Path $ScriptRoot 'lib\SecurityItems.ps1')
. (Join-Path $ScriptRoot 'lib\Review.ps1')

$script:LogFile = $script:Paths.SecurityLog
$script:LogSink = $null   # set after TextBox is created

if (-not (Test-Admin) -and -not $NoElevate) {
    [void][System.Windows.Forms.MessageBox]::Show(
        'Windows Security Optimizer needs administrator rights.' + [Environment]::NewLine + [Environment]::NewLine + 'Click OK to restart with elevation.',
        'Admin required', 'OK', 'Information')
    Restart-Admin -Arguments @('-NoElevate'.Substring(1))
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Windows Security Optimizer'
$form.ClientSize = New-Object System.Drawing.Size(650, 466)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$grp = New-Object System.Windows.Forms.GroupBox
$grp.Text = 'Hardening items (tick to apply)'
$grp.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$grp.Location = New-Object System.Drawing.Point(10, 8)
$grp.Size = New-Object System.Drawing.Size(630, 190)

# Pick only the 6 safe items the standalone exposes.
$visibleItems = @('cloud','firewall','scan','lock','browsers','restore')
$visibleText  = @{
    cloud    = '1. Defender cloud protection (block at first sight)'
    firewall = '2. Firewall: block all unsolicited inbound by default'
    scan     = '3. Daily Defender quick scan at 03:00'
    lock     = '4. Auto-lock the screen after 10 min idle'
    browsers = '5. Harden Edge + Chrome (safe browsing, block bad downloads)'
    restore  = '6. Enable System Restore + weekly restore points'
}

$script:checks = [System.Collections.ArrayList]::new()
$y = 30
foreach ($id in $visibleItems) {
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $visibleText[$id]
    $cb.AutoSize = $true
    $cb.Checked = $true
    $cb.Tag = $id
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

$form.Controls.Add($btnApply) | Out-Null
$form.Controls.Add($btnRestore) | Out-Null
$form.Controls.Add($btnReview) | Out-Null
$form.Controls.Add($lblLog) | Out-Null
$form.Controls.Add($script:logBox) | Out-Null

# Wire the sink AFTER the TextBox exists.
$script:LogSink = {
    param([string]$line)
    if ($script:logBox -and -not $script:logBox.IsDisposed) {
        try {
            if ($script:logBox.InvokeRequired) {
                $script:logBox.Invoke([System.Action]{ $script:logBox.AppendText($line + [Environment]::NewLine) }) | Out-Null
            } else {
                $script:logBox.AppendText($line + [Environment]::NewLine)
            }
        } catch { }
    }
}

$btnApply.add_Click({
    $ids = @($script:checks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    if ($ids.Count -eq 0) {
        Show-Message 'Tick at least one hardening item.' 'Nothing selected' Warn
        return
    }
    Write-Log '=== Security Optimizer started ==='
    foreach ($id in $ids) { Apply-SecurityItem -Id $id }
    Write-Log '=== Security Optimizer finished ==='
    Show-Message 'Hardening applied. A reboot is recommended.' 'Finished' Info
})

$btnRestore.add_Click({
    Restore-Security
    Show-Message 'Restore complete.' 'Finished' Info
})

$btnReview.add_Click({ Save-SecurityReview })

Write-Log 'Ready. Tick hardening items and click Apply checked.'
Write-Log ("Backup folder: " + $script:Paths.SecurityBackup)

if ($SmokeTest) {
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 2000
    $timer.add_Tick({ $form.Close() })
    $timer.Start()
}

[void]$form.ShowDialog()
