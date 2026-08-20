<#
.SYNOPSIS
  System Optimizer - the unified GUI. Thin shim over lib/*.ps1.
  Tab 1 Performance + Services, Tab 2 Security, Tab 3 Maintenance, Tab 4 Repair.

.DESCRIPTION
  This script is intentionally a UI shell. All real logic lives in lib/
  (Common.ps1, ServiceCatalog.ps1, SecurityItems.ps1, MaintenanceItems.ps1,
  Repair.ps1, Review.ps1). Read those for behaviour details.
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
. (Join-Path $ScriptRoot 'lib\SecurityItems.ps1')
. (Join-Path $ScriptRoot 'lib\MaintenanceItems.ps1')
. (Join-Path $ScriptRoot 'lib\Repair.ps1')
. (Join-Path $ScriptRoot 'lib\Review.ps1')
. (Join-Path $ScriptRoot 'lib\BackupRestore.ps1')

$script:LogFile = $script:Paths.UnifiedLog
$script:LogSink = $null

if (-not (Test-Admin) -and -not $NoElevate) {
    [void][System.Windows.Forms.MessageBox]::Show(
        'System Optimizer needs administrator rights.' + [Environment]::NewLine + [Environment]::NewLine + 'Click OK to restart with elevation.',
        'Admin required', 'OK', 'Information')
    Restart-Admin
}

# --------------------------------------------------------------------------
# Form
# --------------------------------------------------------------------------
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
$form.Controls.Add($tabs) | Out-Null

# --------------------------------------------------------------------------
# Tab 1 - Performance & Services
# --------------------------------------------------------------------------
$script:svcChecks = [System.Collections.ArrayList]::new()

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
$gbSafe.Controls.Add($flowSafe) | Out-Null

$gbOpt = New-Object System.Windows.Forms.GroupBox
$gbOpt.Text = 'OPTIONAL services (may affect features)'
$gbOpt.Location = New-Object System.Drawing.Point(434, 6)
$gbOpt.Size = New-Object System.Drawing.Size(420, 320)
$flowOpt = New-Object System.Windows.Forms.FlowLayoutPanel
$flowOpt.Location = New-Object System.Drawing.Point(10, 22)
$flowOpt.Size = New-Object System.Drawing.Size(400, 290)
$flowOpt.AutoScroll = $true; $flowOpt.WrapContents = $false; $flowOpt.FlowDirection = 'TopDown'
$gbOpt.Controls.Add($flowOpt) | Out-Null

foreach ($n in $script:ServiceGroups.Safe) {
    $svc  = Get-Service -Name $n -ErrorAction SilentlyContinue
    $disp = if ($svc) { $svc.DisplayName } else { $null }
    $label = if ($disp) { "$n  ($disp)" } else { $n }
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $label; $cb.Font = New-Object System.Drawing.Font('Consolas', 9)
    $cb.AutoSize = $true; $cb.Checked = $true; $cb.Tag = $n
    [void]$script:svcChecks.Add($cb); $flowSafe.Controls.Add($cb)
}
foreach ($n in $script:ServiceGroups.Optional) {
    $svc  = Get-Service -Name $n -ErrorAction SilentlyContinue
    $disp = if ($svc) { $svc.DisplayName } else { $null }
    $label = if ($disp) { "$n  ($disp)" } else { $n }
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $label; $cb.Font = New-Object System.Drawing.Font('Consolas', 9)
    $cb.AutoSize = $true; $cb.Checked = $false; $cb.Tag = $n
    [void]$script:svcChecks.Add($cb); $flowOpt.Controls.Add($cb)
}

$tabPerf.Controls.Add($gbSafe) | Out-Null
$tabPerf.Controls.Add($gbOpt) | Out-Null

$btnDisable = New-Object System.Windows.Forms.Button; $btnDisable.Text = 'Disable services (selected)'; $btnDisable.Size = New-Object System.Drawing.Size(160,30); $btnDisable.Location = New-Object System.Drawing.Point(6, 336)
$btnRestoreSvc = New-Object System.Windows.Forms.Button; $btnRestoreSvc.Text = 'Restore services'; $btnRestoreSvc.Size = New-Object System.Drawing.Size(130,30); $btnRestoreSvc.Location = New-Object System.Drawing.Point(174, 336)
$btnVerifySvc = New-Object System.Windows.Forms.Button; $btnVerifySvc.Text = 'Verify services'; $btnVerifySvc.Size = New-Object System.Drawing.Size(130,30); $btnVerifySvc.Location = New-Object System.Drawing.Point(312, 336)
$btnRestoreOpt = New-Object System.Windows.Forms.Button; $btnRestoreOpt.Text = 'Restore optional only'; $btnRestoreOpt.Size = New-Object System.Drawing.Size(150,30); $btnRestoreOpt.Location = New-Object System.Drawing.Point(450, 336)
$tabPerf.Controls.Add($btnDisable) | Out-Null
$tabPerf.Controls.Add($btnRestoreSvc) | Out-Null
$tabPerf.Controls.Add($btnVerifySvc) | Out-Null
$tabPerf.Controls.Add($btnRestoreOpt) | Out-Null

$lblOptHint = New-Object System.Windows.Forms.Label
$lblOptHint.Text = "TIP: OPTIONAL services can disable printing, Remote Desktop, Bluetooth, search or scanners. If a feature stops working, use 'Restore optional only'."
$lblOptHint.Location = New-Object System.Drawing.Point(8, 374)
$lblOptHint.Size = New-Object System.Drawing.Size(860, 40)
$lblOptHint.ForeColor = [System.Drawing.Color]::FromArgb(150,110,0)
$tabPerf.Controls.Add($lblOptHint) | Out-Null

$tabs.TabPages.Add($tabPerf) | Out-Null

# --------------------------------------------------------------------------
# Tab 2 - Security
# --------------------------------------------------------------------------
$script:secChecks = [System.Collections.ArrayList]::new()

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

$n = 0
foreach ($it in $script:SecurityItems) {
    $n++
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = "$n.  $($it.text)"; $cb.AutoSize = $true; $cb.Checked = $true; $cb.Tag = $it.id
    [void]$script:secChecks.Add($cb); $flowSec.Controls.Add($cb)
}
$gbSec.Controls.Add($flowSec) | Out-Null
$tabSec.Controls.Add($gbSec) | Out-Null

$btnApplySec = New-Object System.Windows.Forms.Button; $btnApplySec.Text = 'Apply security (selected)'; $btnApplySec.Size = New-Object System.Drawing.Size(150,30); $btnApplySec.Location = New-Object System.Drawing.Point(6, 336)
$btnRestoreSec = New-Object System.Windows.Forms.Button; $btnRestoreSec.Text = 'Restore security'; $btnRestoreSec.Size = New-Object System.Drawing.Size(130,30); $btnRestoreSec.Location = New-Object System.Drawing.Point(164, 336)
$btnReviewSec = New-Object System.Windows.Forms.Button; $btnReviewSec.Text = 'Security review'; $btnReviewSec.Size = New-Object System.Drawing.Size(130,30); $btnReviewSec.Location = New-Object System.Drawing.Point(302, 336)
$btnRestoreCheckedSec = New-Object System.Windows.Forms.Button; $btnRestoreCheckedSec.Text = 'Restore checked'; $btnRestoreCheckedSec.Size = New-Object System.Drawing.Size(150,30); $btnRestoreCheckedSec.Location = New-Object System.Drawing.Point(440, 336)
$btnExplainSec = New-Object System.Windows.Forms.Button; $btnExplainSec.Text = 'Explain this'; $btnExplainSec.Size = New-Object System.Drawing.Size(120,30); $btnExplainSec.Location = New-Object System.Drawing.Point(598, 336)
$tabSec.Controls.Add($btnApplySec) | Out-Null
$tabSec.Controls.Add($btnRestoreSec) | Out-Null
$tabSec.Controls.Add($btnReviewSec) | Out-Null
$tabSec.Controls.Add($btnRestoreCheckedSec) | Out-Null
$tabSec.Controls.Add($btnExplainSec) | Out-Null

$tabs.TabPages.Add($tabSec) | Out-Null

# --------------------------------------------------------------------------
# Tab 3 - Maintenance
# --------------------------------------------------------------------------
$script:maintChecks = [System.Collections.ArrayList]::new()

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
$preChecked = 'cleantemp','wucleanup','trimssd','flushdns','gamedvr','faststartup','tips'
$n = 0
foreach ($it in $script:MaintenanceItems) {
    $n++
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = "$n.  $($it.text)"; $cb.AutoSize = $true
    $cb.Checked = ($preChecked -contains $it.id); $cb.Tag = $it.id
    [void]$script:maintChecks.Add($cb); $flowMaint.Controls.Add($cb)
}
$gbMaint.Controls.Add($flowMaint) | Out-Null
$tabMaint.Controls.Add($gbMaint) | Out-Null

$btnMaintRun = New-Object System.Windows.Forms.Button; $btnMaintRun.Text = 'Run selected cleanup'; $btnMaintRun.Size = New-Object System.Drawing.Size(150,30); $btnMaintRun.Location = New-Object System.Drawing.Point(6, 336)
$btnMaintRestore = New-Object System.Windows.Forms.Button; $btnMaintRestore.Text = 'Restore settings'; $btnMaintRestore.Size = New-Object System.Drawing.Size(140,30); $btnMaintRestore.Location = New-Object System.Drawing.Point(164, 336)
$btnMaintReport = New-Object System.Windows.Forms.Button; $btnMaintReport.Text = 'Cleanup report'; $btnMaintReport.Size = New-Object System.Drawing.Size(130,30); $btnMaintReport.Location = New-Object System.Drawing.Point(312, 336)
$btnExplainMaint = New-Object System.Windows.Forms.Button; $btnExplainMaint.Text = 'Explain this'; $btnExplainMaint.Size = New-Object System.Drawing.Size(120,30); $btnExplainMaint.Location = New-Object System.Drawing.Point(450, 336)
$tabMaint.Controls.Add($btnMaintRun) | Out-Null
$tabMaint.Controls.Add($btnMaintRestore) | Out-Null
$tabMaint.Controls.Add($btnMaintReport) | Out-Null
$tabMaint.Controls.Add($btnExplainMaint) | Out-Null

$lblMaintHint = New-Object System.Windows.Forms.Label
$lblMaintHint.Text = "TIP: items 1-5 and 11-12 are safe and pre-ticked. Items 6-10 and 13 are optional/off (may delete recoverable files, change visuals/power, or auto-clean restore points). Reversible settings can be undone with 'Restore settings'."
$lblMaintHint.Location = New-Object System.Drawing.Point(8, 374)
$lblMaintHint.Size = New-Object System.Drawing.Size(860, 40)
$lblMaintHint.ForeColor = [System.Drawing.Color]::FromArgb(150,110,0)
$tabMaint.Controls.Add($lblMaintHint) | Out-Null

$tabs.TabPages.Add($tabMaint) | Out-Null

# --------------------------------------------------------------------------
# Tab 4 - System Repair
# --------------------------------------------------------------------------
$script:repairChecks = [System.Collections.ArrayList]::new()
$repairItems = @(
    @{ id='sfc';    text='Verify and repair system files (sfc /scannow)' },
    @{ id='dism';   text='Repair the Windows image (DISM /restorehealth)' },
    @{ id='chkdsk'; text='Check disk for errors (chkdsk C: /f) - REQUIRES RESTART' }
)

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

foreach ($it in $repairItems) {
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $it.text; $cb.AutoSize = $true
    $cb.Checked = ($it.id -ne 'chkdsk'); $cb.Tag = $it.id
    [void]$script:repairChecks.Add($cb); $flowRepair.Controls.Add($cb)
}
$gbRepair.Controls.Add($flowRepair) | Out-Null
$tabRepair.Controls.Add($gbRepair) | Out-Null

$btnRepairRun = New-Object System.Windows.Forms.Button; $btnRepairRun.Text = 'Run selected repairs'; $btnRepairRun.Size = New-Object System.Drawing.Size(160,30); $btnRepairRun.Location = New-Object System.Drawing.Point(6, 214)
$tabRepair.Controls.Add($btnRepairRun) | Out-Null

$lblRepairHint = New-Object System.Windows.Forms.Label
$lblRepairHint.Text = "NOTE: repairs can take a long time (sfc 5-10 min, DISM 10-20+ min). chkdsk needs a restart. Repairs are NOT part of 'Apply ALL' - run them here when needed."
$lblRepairHint.Location = New-Object System.Drawing.Point(8, 252)
$lblRepairHint.Size = New-Object System.Drawing.Size(860, 40)
$lblRepairHint.ForeColor = [System.Drawing.Color]::FromArgb(150,110,0)
$tabRepair.Controls.Add($lblRepairHint) | Out-Null
$tabs.TabPages.Add($tabRepair) | Out-Null

# --------------------------------------------------------------------------
# Tab 5 - Backup & Restore
# --------------------------------------------------------------------------
$tabBk = New-Object System.Windows.Forms.TabPage
$tabBk.Text = 'Backup & Restore'
$tabBk.Padding = New-Object System.Windows.Forms.Padding(6)
$tabBk.AutoScroll = $true

$gbBk = New-Object System.Windows.Forms.GroupBox
$gbBk.Text = 'Back up / restore your user settings (to a USB drive)'
$gbBk.Location = New-Object System.Drawing.Point(6, 6)
$gbBk.Size = New-Object System.Drawing.Size(852, 160)
$lblBk = New-Object System.Windows.Forms.Label
$lblBk.Text = "Backs up safe, portable items: browser bookmarks, Wi-Fi profiles, user registry settings, and this tool's profile.`nPasswords are NOT backed up (security) - use a password manager for those."
$lblBk.Location = New-Object System.Drawing.Point(12, 24)
$lblBk.Size = New-Object System.Drawing.Size(820, 60)
$lblBk.ForeColor = [System.Drawing.Color]::FromArgb(60,60,60)
$gbBk.Controls.Add($lblBk) | Out-Null

$btnBackup = New-Object System.Windows.Forms.Button; $btnBackup.Text = 'Backup settings to USB'; $btnBackup.Size = New-Object System.Drawing.Size(180,30); $btnBackup.Location = New-Object System.Drawing.Point(12, 100)
$btnRestoreBk = New-Object System.Windows.Forms.Button; $btnRestoreBk.Text = 'Restore from USB'; $btnRestoreBk.Size = New-Object System.Drawing.Size(150,30); $btnRestoreBk.Location = New-Object System.Drawing.Point(200, 100)
$btnPreflight = New-Object System.Windows.Forms.Button; $btnPreflight.Text = 'Pre-flight check'; $btnPreflight.Size = New-Object System.Drawing.Size(130,30); $btnPreflight.Location = New-Object System.Drawing.Point(358, 100)
$gbBk.Controls.Add($btnBackup) | Out-Null
$gbBk.Controls.Add($btnRestoreBk) | Out-Null
$gbBk.Controls.Add($btnPreflight) | Out-Null

$lblBkNote = New-Object System.Windows.Forms.Label
$lblBkNote.Text = "TIP: plug in a USB drive, then Backup settings to USB. Keep the USB safe. On a new/problem PC, Restore from USB brings back bookmarks, Wi-Fi and settings."
$lblBkNote.Location = New-Object System.Drawing.Point(8, 178)
$lblBkNote.Size = New-Object System.Drawing.Size(860, 30)
$lblBkNote.ForeColor = [System.Drawing.Color]::FromArgb(150,110,0)
$tabBk.Controls.Add($gbBk) | Out-Null
$tabBk.Controls.Add($lblBkNote) | Out-Null

$tabs.TabPages.Add($tabBk) | Out-Null

# --------------------------------------------------------------------------
# Bottom master controls
# --------------------------------------------------------------------------
$btnApplyAll = New-Object System.Windows.Forms.Button; $btnApplyAll.Text = 'Apply ALL selected'; $btnApplyAll.Size = New-Object System.Drawing.Size(150,34); $btnApplyAll.Location = New-Object System.Drawing.Point(10, 442)
$btnRestoreAll = New-Object System.Windows.Forms.Button; $btnRestoreAll.Text = 'Restore ALL'; $btnRestoreAll.Size = New-Object System.Drawing.Size(120,34); $btnRestoreAll.Location = New-Object System.Drawing.Point(168, 442)
$btnReviewAll = New-Object System.Windows.Forms.Button; $btnReviewAll.Text = 'Full review'; $btnReviewAll.Size = New-Object System.Drawing.Size(120,34); $btnReviewAll.Location = New-Object System.Drawing.Point(296, 442)
$btnHelp = New-Object System.Windows.Forms.Button; $btnHelp.Text = 'Help'; $btnHelp.Size = New-Object System.Drawing.Size(80,34); $btnHelp.Location = New-Object System.Drawing.Point(424, 442)
$btnExport = New-Object System.Windows.Forms.Button; $btnExport.Text = 'Export'; $btnExport.Size = New-Object System.Drawing.Size(80,34); $btnExport.Location = New-Object System.Drawing.Point(512, 442)
$btnImport = New-Object System.Windows.Forms.Button; $btnImport.Text = 'Import'; $btnImport.Size = New-Object System.Drawing.Size(80,34); $btnImport.Location = New-Object System.Drawing.Point(600, 442)
$btnUndoLast = New-Object System.Windows.Forms.Button; $btnUndoLast.Text = 'Undo last'; $btnUndoLast.Size = New-Object System.Drawing.Size(90,34); $btnUndoLast.Location = New-Object System.Drawing.Point(690, 442)
$form.Controls.Add($btnApplyAll) | Out-Null
$form.Controls.Add($btnRestoreAll) | Out-Null
$form.Controls.Add($btnReviewAll) | Out-Null
$form.Controls.Add($btnHelp) | Out-Null
$form.Controls.Add($btnExport) | Out-Null
$form.Controls.Add($btnImport) | Out-Null
$form.Controls.Add($btnUndoLast) | Out-Null

$lblLog = New-Object System.Windows.Forms.Label; $lblLog.Text = 'Log:'; $lblLog.Location = New-Object System.Drawing.Point(10, 486)
$form.Controls.Add($lblLog) | Out-Null

$script:logBox = New-Object System.Windows.Forms.TextBox
$script:logBox.Multiline = $true; $script:logBox.ReadOnly = $true; $script:logBox.ScrollBars = 'Vertical'
$script:logBox.BackColor = [System.Drawing.Color]::FromArgb(32,32,32); $script:logBox.ForeColor = [System.Drawing.Color]::White
$script:logBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$script:logBox.Location = New-Object System.Drawing.Point(10, 506); $script:logBox.Size = New-Object System.Drawing.Size(880, 142)
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

# --------------------------------------------------------------------------
# v1.4 helpers: Explain this, Export/Import settings
# --------------------------------------------------------------------------
function Show-ItemExplanations {
    param($Items, $Checks)
    $checked = @($Checks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    if ($checked.Count -eq 0) { Show-Message 'Tick the items you want to learn about.' 'Explain' Warn; return }
    $lines = @()
    foreach ($it in $Items) {
        if ($checked -contains $it.id) {
            $d = if ($it.desc) { $it.desc } else { '(no description)' }
            $lines += ($it.text + "`n    " + $d)
        }
    }
    Show-Message ($lines -join "`n`n") 'What these do' Info
}

function Export-Settings {
    $data = @{
        services = @($script:svcChecks  | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
        security = @($script:secChecks   | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
        maint    = @($script:maintChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
        repair   = @($script:repairChecks| Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    }
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter = 'JSON settings|*.json'
    $dlg.FileName = 'System-Optimizer-profile.json'
    if ($dlg.ShowDialog() -eq 'OK') {
        try { $data | ConvertTo-Json | Set-Content -LiteralPath $dlg.FileName -Encoding UTF8; Show-Message ("Settings saved to " + $dlg.FileName) 'Export' Info }
        catch { Show-Message ("Export failed: " + $_.Exception.Message) 'Error' }
    }
}

function Import-Settings {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'JSON settings|*.json'
    if ($dlg.ShowDialog() -eq 'OK') {
        try {
            $d = Get-Content -LiteralPath $dlg.FileName -Raw | ConvertFrom-Json
            foreach ($cb in $script:svcChecks)   { $cb.Checked = @($d.services) -contains $cb.Tag }
            foreach ($cb in $script:secChecks)   { $cb.Checked = @($d.security) -contains $cb.Tag }
            foreach ($cb in $script:maintChecks) { $cb.Checked = @($d.maint)    -contains $cb.Tag }
            foreach ($cb in $script:repairChecks){ $cb.Checked = @($d.repair)   -contains $cb.Tag }
            Show-Message 'Settings imported. Review the checkboxes before applying.' 'Import' Info
        } catch { Show-Message ("Import failed: " + $_.Exception.Message) 'Error' }
    }
}

function Save-LastRun {
    param([string[]]$services = @(), [string[]]$security = @(), [string[]]$maint = @())
    $data = @{ time = (Get-Date).ToString('o'); services = @($services); security = @($security); maint = @($maint) }
    New-Item -ItemType Directory -Path $script:Paths.SystemBackup -Force | Out-Null
    $data | ConvertTo-Json | Set-Content -LiteralPath $script:Paths.LastRunFile -Encoding UTF8
}

function Undo-LastRun {
    $p = $script:Paths.LastRunFile
    if (-not (Test-Path -LiteralPath $p)) { Show-Message 'No last run recorded to undo.' 'Undo last' Warn; return }
    try {
        $d = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
        Write-Log '=== Undo last run ==='
        $svc = @($d.services); $sec = @($d.security); $mt = @($d.maint)
        if ($svc.Count -gt 0) {
            $rows = @(Read-CsvRows -Path $script:Paths.ServicesBackupFile | Where-Object { $svc -contains $_.Name })
            Restore-ServicesRows -Rows $rows
        }
        if ($sec.Count -gt 0) { Restore-SecurityItems -Ids $sec }
        if ($mt.Count -gt 0)  { Restore-MaintenanceItems -Ids $mt }
        Write-Log '=== Undo last run finished ==='
        Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        Show-Message 'Last run undone.' 'Undo last' Info
    } catch {
        Write-Log "ERROR undo last: $($_.Exception.Message)"
        Show-Message ("Undo failed: " + $_.Exception.Message) 'Error'
    }
}

# --------------------------------------------------------------------------
# Click handlers
# --------------------------------------------------------------------------
$btnDisable.add_Click({
    try {
        $names = @($script:svcChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
        if ($names.Count -eq 0) { Show-Message 'Select at least one service.' 'Nothing selected' Warn; return }
        Write-Log '=== Services optimize started ==='
        Backup-ServicesSnapshot
        Disable-Services -Names $names
        Write-Log '=== Services optimize finished ==='
        Save-LastRun -services $names
        Show-Message "Done. $($names.Count) services processed. Reboot recommended." 'Finished' Info
    } catch {
        Write-Log "ERROR: $($_.Exception.Message)"
        Show-Message ("Could not complete: " + $_.Exception.Message) 'Error'
    }
})

$btnRestoreSvc.add_Click({
    Write-Log '=== Services restore ==='
    Restore-Services
    Write-Log '=== finished ==='
    Show-Message 'Services restore complete.' 'Finished' Info
})

$btnVerifySvc.add_Click({
    Write-Log '--- Verify services ---'
    Test-ServicesDisabled
})

$btnRestoreOpt.add_Click({
    Write-Log '--- Restore optional services ---'
    Restore-OptionalServices
    Show-Message 'Optional services restored (print, Remote Desktop, Bluetooth, etc.).' 'Finished' Info
})

$btnApplySec.add_Click({
    $ids = @($script:secChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    if ($ids.Count -eq 0) { Show-Message 'Tick at least one hardening item.' 'Nothing selected' Warn; return }
    # Confirm before any irreversible setting (BitLocker encrypts the drive;
    # Script Host disable breaks .vbs/.js system-wide; lockout locks you out).
    $needsConfirm = $ids -contains 'bitlocker' -or $ids -contains 'officewsh' -or $ids -contains 'lockout'
    if ($needsConfirm) {
        $items = ($ids | Where-Object { $_ -in @('bitlocker','officewsh','lockout') }) -join ', '
        if (-not (Show-YesNo "These checked items can be hard to undo: $items.`n`nContinue?" 'Confirm' Warn)) { return }
    }
    Write-Log '=== Security hardening started ==='
    foreach ($id in $ids) { Apply-SecurityItem -Id $id }
    Write-Log '=== Security hardening finished ==='
    Save-LastRun -security $ids
    Show-Message 'Hardening applied. A reboot is recommended.' 'Finished' Info
})

$btnRestoreSec.add_Click({
    Write-Log '--- Restore security ---'
    Restore-Security
    Show-Message 'Security restore complete.' 'Finished' Info
})

$btnReviewSec.add_Click({ Write-Log '--- Security review ---'; Save-SecurityReview })

$btnRestoreCheckedSec.add_Click({
    $ids = @($script:secChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    if ($ids.Count -eq 0) { Show-Message 'Tick the hardening items you want to restore.' 'Nothing selected' Warn; return }
    Write-Log '--- Restore checked (security) ---'
    Restore-SecurityItems -Ids $ids
    Show-Message 'Checked items restored to their previous settings.' 'Finished' Info
})

$btnApplyAll.add_Click({
    try {
        # Pre-flight check: admin, disk space, restore point, USB-for-BitLocker
        $secIds = @($script:secChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
        if (-not (Test-PreFlight -SecurityIds $secIds)) { return }
        # Confirm before destructive / risky items even when run via "Apply ALL".
        $maintIds = @($script:maintChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
        if ($secIds -contains 'bitlocker' -or $secIds -contains 'officewsh' -or $secIds -contains 'lockout' `
            -or $maintIds -contains 'recyclebin' -or $maintIds -contains 'cleantemp' -or $maintIds -contains 'browscache') {
            if (-not (Show-YesNo 'Apply ALL will also: enable BitLocker, disable Script Host + macros, set account lockout, empty the recycle bin, clear temp + browser caches.`n`nProceed?' 'Confirm' Warn)) { return }
        }
        $svc = @($script:svcChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
        Write-Log '===== APPLY ALL ====='
        if ($svc.Count -gt 0) { Backup-ServicesSnapshot; Disable-Services -Names $svc }
        foreach ($id in $secIds)   { Apply-SecurityItem -Id $id }
        foreach ($id in $maintIds) { Invoke-MaintenanceItem -Id $id }
        Write-Log '===== APPLY ALL finished ====='
        Save-LastRun -services $svc -security $secIds -maint $maintIds
        Show-Message 'All selected items applied. A reboot is recommended.' 'Finished' Info
    } catch {
        Write-Log "ERROR: $($_.Exception.Message)"
        Show-Message ("Could not complete: " + $_.Exception.Message) 'Error'
    }
})

$btnRestoreAll.add_Click({
    Write-Log '===== RESTORE ALL ====='
    Restore-Services
    Restore-Security
    Restore-Maintenance
    Write-Log '===== RESTORE ALL finished ====='
    Show-Message 'All settings restored to defaults.' 'Finished' Info
})

$btnReviewAll.add_Click({
    Write-Log '--- Full review ---'
    Test-ServicesDisabled
    Save-SecurityReview
    Get-MaintenanceReport
    Get-DiagnosticsReport
})

$btnHelp.add_Click({ Show-SoHelpWindow })
$btnExplainSec.add_Click({ Show-ItemExplanations -Items $script:SecurityItems -Checks $script:secChecks })
$btnExplainMaint.add_Click({ Show-ItemExplanations -Items $script:MaintenanceItems -Checks $script:maintChecks })
$btnExport.add_Click({ Export-Settings })
$btnImport.add_Click({ Import-Settings })
$btnUndoLast.add_Click({ Undo-LastRun })
$btnBackup.add_Click({ Backup-UserSettings })
$btnRestoreBk.add_Click({ Restore-UserSettings })
$btnPreflight.add_Click({
    $secIds = @($script:secChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    Test-PreFlight -SecurityIds $secIds
})

$btnMaintRun.add_Click({
    $ids = @($script:maintChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    if ($ids.Count -eq 0) { Show-Message 'Tick at least one cleanup item.' 'Nothing selected' Warn; return }
    if ($ids -contains 'recyclebin') {
        if (-not (Show-YesNo 'Empty the Recycle Bin permanently?' 'Confirm' Warn)) { return }
    }
    Write-Log '=== Maintenance started ==='
    foreach ($id in $ids) { Invoke-MaintenanceItem -Id $id }
    Write-Log '=== Maintenance finished ==='
    Save-LastRun -maint $ids
    Show-Message 'Cleanup finished.' 'Finished' Info
})

$btnMaintRestore.add_Click({
    Write-Log '--- Restore maintenance ---'
    Restore-Maintenance
    Show-Message 'Maintenance settings restored.' 'Finished' Info
})

$btnMaintReport.add_Click({ Write-Log '--- Maintenance report ---'; Get-MaintenanceReport })

$btnRepairRun.add_Click({
    $ids = @($script:repairChecks | Where-Object { $_.Checked } | ForEach-Object { $_.Tag })
    if ($ids.Count -eq 0) { Show-Message 'Tick at least one repair tool.' 'Nothing selected' Warn; return }
    if ($ids -contains 'chkdsk') {
        if (-not (Show-YesNo 'chkdsk will run at the next restart. Continue?' 'Confirm' Warn)) { return }
    }
    Write-Log '=== System repair started (this can take a while) ==='
    foreach ($id in $ids) { Invoke-RepairItem -Id $id }
    Write-Log '=== System repair finished ==='
    Show-Message 'Repair finished.' 'Finished' Info
})

# --------------------------------------------------------------------------
# Help window (RichTextBox; built from HELP.md-ish text)
# --------------------------------------------------------------------------
function Show-SoHelpWindow {
    $helpPath = Join-Path $ScriptRoot 'HELP.md'
    if (-not (Test-Path -LiteralPath $helpPath)) {
        $helpText = 'No HELP.md found beside this script. Please reinstall the package.'
    } else {
        $helpText = Get-Content -LiteralPath $helpPath -Raw -ErrorAction SilentlyContinue
    }
    $hf = New-Object System.Windows.Forms.Form
    $hf.Text = 'System Optimizer - Help / settings guide'
    $hf.ClientSize = New-Object System.Drawing.Size(860, 760)
    $hf.StartPosition = 'CenterParent'
    $hf.MinimizeBox = $false
    $hf.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $rtb = New-Object System.Windows.Forms.RichTextBox
    $rtb.ReadOnly = $true; $rtb.WordWrap = $true; $rtb.ScrollBars = 'Vertical'
    $rtb.Dock = 'Fill'; $rtb.BackColor = [System.Drawing.Color]::White
    $rtb.ForeColor = [System.Drawing.Color]::Black
    $rtb.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $rtb.BorderStyle = 'None'
    $hf.Controls.Add($rtb) | Out-Null
    $cTitle = [System.Drawing.Color]::FromArgb(31,78,121)
    $cHead  = [System.Drawing.Color]::FromArgb(0,90,158)
    $cSub   = [System.Drawing.Color]::FromArgb(31,78,121)
    $cItem  = [System.Drawing.Color]::FromArgb(40,40,40)
    $cBody  = [System.Drawing.Color]::FromArgb(60,60,60)
    $cNote  = [System.Drawing.Color]::FromArgb(150,110,0)
    $cBullet= [System.Drawing.Color]::FromArgb(0,120,0)
    function Emit([string]$text, [string]$style) {
        $rtb.SelectionStart = $rtb.TextLength
        $rtb.SelectionLength = 0
        $b = [System.Drawing.FontStyle]::Bold
        $r = [System.Drawing.FontStyle]::Regular
        $i = [System.Drawing.FontStyle]::Italic
        switch ($style) {
            'h1'    { $rtb.SelectionFont = New-Object System.Drawing.Font('Segoe UI',15,$b); $rtb.SelectionColor = $cTitle }
            'h2'    { $rtb.SelectionFont = New-Object System.Drawing.Font('Segoe UI',12,$b); $rtb.SelectionColor = $cHead }
            'h3'    { $rtb.SelectionFont = New-Object System.Drawing.Font('Segoe UI',11,$b); $rtb.SelectionColor = $cSub }
            'item'  { $rtb.SelectionFont = New-Object System.Drawing.Font('Segoe UI',10,$b); $rtb.SelectionColor = $cItem }
            'note'  { $rtb.SelectionFont = New-Object System.Drawing.Font('Segoe UI',10,$i); $rtb.SelectionColor = $cNote }
            'bullet'{ $rtb.SelectionFont = New-Object System.Drawing.Font('Segoe UI',10,$r); $rtb.SelectionColor = $cBullet }
            default { $rtb.SelectionFont = New-Object System.Drawing.Font('Segoe UI',10,$r); $rtb.SelectionColor = $cBody }
        }
        $rtb.AppendText($text + [Environment]::NewLine)
    }
    foreach ($raw in ($helpText -split "`r?`n")) {
        $line = $raw.TrimEnd()
        if      ($line -match '^=+\s*$')                  { Emit '' 'body'; continue }
        if      ($line -match '^#\s+(.+)$')                { Emit ($line -replace '^#\s+','') 'h1'; continue }
        if      ($line -match '^##\s+(.+)$')               { Emit ($line -replace '^##\s+','') 'h2'; continue }
        if      ($line -match '^###\s+(.+)$')              { Emit ($line -replace '^###\s+','') 'h3'; continue }
        if      ($line -match '^(\d+\.\s+|-\s+|\*\s+)')    { Emit $line 'bullet'; continue }
        if      ($line -match '^(IMPORTANT|Note|Tradeoff|Restore does NOT|Warning|TIP:|NOTE:)') { Emit $line 'note'; continue }
        Emit $line 'body'
    }
    [void]$hf.ShowDialog()
}

# --------------------------------------------------------------------------
# Open
# --------------------------------------------------------------------------
Write-Log 'Ready. Pick items on the tabs, then Apply. Restore ALL returns everything to defaults.'
Write-Log ("Backups: " + $script:Paths.ServiceBackup + "  and  " + $script:Paths.SecurityBackup)

if ($SmokeTest) {
    $marker = Join-Path $env:TEMP 'so_smoke.txt'
    New-Item -ItemType Directory -Path (Split-Path $marker) -Force | Out-Null
    Set-Content -Path $marker -Value 'SmokeTest bound = TRUE'
    $cb = [System.Threading.TimerCallback]{ param($state)
        try { $script:smokeTimer.Dispose() } catch { }
        try { $form.Invoke([System.Action]{ $form.Close() }) | Out-Null } catch { }
    }
    $script:smokeTimer = New-Object System.Threading.Timer($cb, $null, 3000, -1)
}

[void]$form.ShowDialog()
if ($SmokeTest) { Write-Output 'SMOKE OK' }
