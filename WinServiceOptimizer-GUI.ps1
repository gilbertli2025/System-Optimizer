<#
.SYNOPSIS
  Windows Services Optimizer - GUI edition (thin shim). Real logic lives in
  lib/*.ps1.

.DESCRIPTION
  Two checkbox groups (SAFE pre-checked, OPTIONAL unchecked). Buttons:
  Optimize, Restore, Verify, "Safe defaults".

.EXAMPLE
  WinServiceOptimizer-GUI.exe
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

$ScriptRoot = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { (Get-Location).Path }
. (Join-Path $ScriptRoot 'lib\Common.ps1')
. (Join-Path $ScriptRoot 'lib\ServiceCatalog.ps1')

$script:LogFile = $script:Paths.ServicesLog
$script:LogSink = $null

if (-not (Test-Admin) -and -not $NoElevate) {
    [void][System.Windows.Forms.MessageBox]::Show(
        'Windows Services Optimizer needs administrator rights.' + [Environment]::NewLine + [Environment]::NewLine + 'Click OK to restart with elevation.',
        'Admin required', 'OK', 'Information')
    Restart-Admin
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Windows Services Optimizer'
$form.ClientSize = New-Object System.Drawing.Size(790, 600)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

function New-ServiceGroup {
    param([string]$Title, [string[]]$Names, [bool]$CheckedInitial, [int]$X)
    $gb = New-Object System.Windows.Forms.GroupBox
    $gb.Text = $Title
    $gb.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $gb.Location = New-Object System.Drawing.Point($X, 8)
    $gb.Size = New-Object System.Drawing.Size(385, 400)
    $fl = New-Object System.Windows.Forms.FlowLayoutPanel
    $fl.Location = New-Object System.Drawing.Point(10, 25)
    $fl.Size = New-Object System.Drawing.Size(365, 368)
    $fl.AutoScroll = $true
    $fl.WrapContents = $false
    $fl.FlowDirection = 'TopDown'
    if ($null -eq $script:allChecks) { $script:allChecks = [System.Collections.ArrayList]::new() }
    foreach ($name in $Names) {
        $cb = New-Object System.Windows.Forms.CheckBox
        $svc  = Get-Service -Name $name -ErrorAction SilentlyContinue
        $disp = if ($svc) { $svc.DisplayName } else { $null }
        $cb.Text = if ($disp) { "$name  ($disp)" } else { $name }
        $cb.Font = New-Object System.Drawing.Font('Consolas', 9)
        $cb.AutoSize = $true
        $cb.Checked = $CheckedInitial
        $cb.Tag = $name
        [void]$script:allChecks.Add($cb)
        $fl.Controls.Add($cb)
    }
    $gb.Controls.Add($fl) | Out-Null
    return ,$gb
}

$script:allChecks = [System.Collections.ArrayList]::new()
$gbSafe = New-ServiceGroup 'SAFE services (recommended)' $script:ServiceGroups.Safe $true 10
$gbOpt  = New-ServiceGroup 'OPTIONAL services (affect features)' $script:ServiceGroups.Optional $false 410
$form.Controls.Add($gbSafe) | Out-Null
$form.Controls.Add($gbOpt) | Out-Null

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

$form.Controls.Add($btnOptimize) | Out-Null
$form.Controls.Add($btnRestore) | Out-Null
$form.Controls.Add($btnVerify) | Out-Null
$form.Controls.Add($btnDefaults) | Out-Null
$form.Controls.Add($lblLog) | Out-Null
$form.Controls.Add($script:logBox) | Out-Null

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

function Get-Selected {
    $names = @()
    foreach ($cb in $script:allChecks) { if ($cb.Checked) { $names += $cb.Tag } }
    return ,$names
}

$btnOptimize.add_Click({
    $names = @(Get-Selected)
    if ($names.Count -eq 0) {
        Show-Message 'Select at least one service.' 'Nothing selected' Warn
        return
    }
    Write-Log '=== Windows Services Optimizer started ==='
    Backup-ServicesSnapshot     # snapshot ONCE, only on apply (bug fix)
    Disable-Services -Names $names
    Write-Log '=== Optimization finished ==='
    Show-Message "Done. $($names.Count) selected services processed.`nReboot recommended." 'Finished' Info
})

$btnRestore.add_Click({
    Write-Log '=== Windows Services Optimizer started ==='
    Restore-Services            # does NOT snapshot (bug fix)
    Write-Log '=== Optimization finished ==='
    Show-Message 'Restore complete.' 'Finished' Info
})

$btnVerify.add_Click({ Write-Log '--- Verification ---'; Test-ServicesFull })

$btnDefaults.add_Click({
    foreach ($cb in $script:allChecks) { $cb.Checked = ($script:ServiceGroups.Safe -contains $cb.Tag) }
})

Write-Log 'Ready. Pick services, then click Optimize selected.'
Write-Log ("Backup/log folder: " + $script:Paths.ServiceBackup)

if ($SmokeTest) {
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 2000
    $timer.add_Tick({ $form.Close() })
    $timer.Start()
}

[void]$form.ShowDialog()
