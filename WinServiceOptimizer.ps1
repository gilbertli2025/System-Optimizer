<#
.SYNOPSIS
  Windows Services Optimizer - console edition (thin shim). Real logic in lib/.

.EXAMPLE
  Windows-Services-Optimizer.exe                # menu
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

$ErrorActionPreference = 'Stop'

$ScriptRoot = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { (Get-Location).Path }
. (Join-Path $ScriptRoot 'lib\Common.ps1')
. (Join-Path $ScriptRoot 'lib\ServiceCatalog.ps1')

$script:LogFile        = $script:Paths.ServicesLog
$script:LogMirrorHost  = $true

function Show-List {
    Write-Host "`nSAFE (disabled by default):"
    $script:ServiceGroups.Safe | ForEach-Object { Write-Host ("  {0,-24} {1}" -f $_, (Get-CurrentStartType $_)) }
    Write-Host "`nOPTIONAL (only with -IncludeOptional):"
    $script:ServiceGroups.Optional | ForEach-Object { Write-Host ("  {0,-24} {1}" -f $_, (Get-CurrentStartType $_)) }
    Write-Host "`nBackup/log folder: $($script:Paths.ServiceBackup)"
}

function Invoke-VerifyConsole {
    # Full verify mode with colored PASS/FAIL/WARN counters
    $p = 0; $f = 0; $w = 0
    function Report { param([string]$state, [string]$msg)
        switch ($state) {
            'PASS'  { $script:p++; Write-Host "  [PASS]  $msg" -ForegroundColor Green }
            'FAIL'  { $script:f++; Write-Host "  [FAIL]  $msg" -ForegroundColor Red }
            'WARN'  { $script:w++; Write-Host "  [WARN]  $msg" -ForegroundColor Yellow }
            default { Write-Host "  [INFO]  $msg" -ForegroundColor Cyan }
        }
    }
    Write-Host '=== Verification Report ===' -ForegroundColor White
    Write-Host ('Date/time: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -ForegroundColor Gray
    if (-not (Test-Path -LiteralPath $script:Paths.ServiceBackup)) {
        Write-Host "No backup folder found at $($script:Paths.ServiceBackup)." -ForegroundColor Red
        Write-Host 'The optimizer has NOT been run on this PC.' -ForegroundColor Yellow
        return 2
    }
    $ran = $false
    if (Test-Path -LiteralPath $script:Paths.ServicesLog) {
        $log = Get-Content -LiteralPath $script:Paths.ServicesLog -ErrorAction SilentlyContinue
        if ($log -match 'Optimizer started') {
            $ran = $true
            Report PASS 'Optimization run detected in log.'
            if ($log -match '=== Optimization finished ===') { Report PASS 'Run completed with a finish marker.' }
            else { Report WARN 'Run started but no finish marker found (may have been interrupted).' }
        } else { Report WARN 'Log exists but no start marker - optimization may not have run.' }
    } else { Report FAIL "Log file not found ($($script:Paths.ServicesLog))." }

    if (-not (Test-Path -LiteralPath $script:Paths.ServicesBackupFile)) {
        Report FAIL "Backup file not found ($($script:Paths.ServicesBackupFile))."
        return 2
    }
    $rows = Read-CsvRows -Path $script:Paths.ServicesBackupFile
    if ($rows.Count -eq 0) {
        Write-Host 'Backup file is empty - no services were targeted.' -ForegroundColor Yellow
        return 2
    }
    Write-Host "`nServices targeted: $($rows.Count)" -ForegroundColor White
    foreach ($row in $rows) {
        $svc = Get-Service -Name $row.Name -ErrorAction SilentlyContinue
        if (-not $svc) { Report WARN "$($row.Name) - service no longer exists."; continue }
        $type = $svc.StartType
        if ($type -eq 'Disabled') { Report PASS "$($row.Name) - disabled (current: $type)." }
        else                       { Report FAIL "$($row.Name) - expected Disabled but current is $type." }
    }
    if ($ran -and (Test-Path -LiteralPath $script:Paths.ServicesLog)) {
        $errLines = Get-Content -LiteralPath $script:Paths.ServicesLog -ErrorAction SilentlyContinue | Where-Object { $_ -match '^ERROR' }
        if ($errLines) {
            Report FAIL 'The log contains error(s):'
            $errLines | ForEach-Object { Write-Host "       $_" -ForegroundColor Red }
        } else { Report PASS 'No errors found in the optimization log.' }
    }
    if (Test-Path -LiteralPath $script:Paths.ServicesSnapshot) {
        Write-Host "`nProtected / critical services (must be unchanged):" -ForegroundColor White
        $snap  = @(Import-Csv -LiteralPath $script:Paths.ServicesSnapshot -ErrorAction SilentlyContinue)
        $checked = 0
        foreach ($row in $snap) {
            if ($script:ServiceGroups.Protected -notcontains $row.Name) { continue }
            $cur = Get-Service -Name $row.Name -ErrorAction SilentlyContinue
            if (-not $cur) { continue }
            $checked++
            $norm = switch ($row.StartMode) { 'Auto' { 'Automatic' } 'AutoStart' { 'Automatic' } default { $row.StartMode } }
            if ($norm -eq $cur.StartType) { Report PASS "$($row.Name) - unchanged ($($row.StartMode))." }
            else                          { Report WARN "$($row.Name) - changed from $($row.StartMode) to $($cur.StartType)." }
        }
        if ($checked -eq 0) { Report WARN 'No protected services found in snapshot.' }
    } else { Report WARN 'Snapshot file missing - cannot verify protected services.' }

    Write-Host ''
    Write-Host "Summary:  PASS=$p  FAIL=$f  WARN=$w" -ForegroundColor White
    if     ($f -gt 0)   { Write-Host 'RESULT: Issues found.' -ForegroundColor Red; return 1 }
    elseif (-not $ran)  { Write-Host 'RESULT: Re-run optimization to confirm.' -ForegroundColor Yellow; return 1 }
    else                { Write-Host 'RESULT: OK.' -ForegroundColor Green; return 0 }
}

function Invoke-Action {
    param([string]$action)
    switch ($action) {
        'Verify' { Invoke-VerifyConsole; return }
        'List'   { Show-List; return }
    }
    if (-not (Test-Admin)) {
        $sw = @("-$action")
        if ($IncludeOptional -and $action -eq 'Optimize') { $sw += '-IncludeOptional' }
        Restart-Admin -Arguments $sw
        return
    }
    switch ($action) {
        'Optimize' {
            Write-Log "=== Windows Services Optimizer started ==="
            Backup-ServicesSnapshot      # snapshot only on apply
            Disable-Services -Names $script:ServiceGroups.Safe
            if ($IncludeOptional) { Disable-Services -Names $script:ServiceGroups.Optional }
            Write-Log "=== Optimization finished ==="
            Write-Host "`nDone. Backup at $($script:Paths.ServicesBackupFile). To revert, run -Restore." -ForegroundColor Green
        }
        'Restore' {
            Write-Log "=== Windows Services Optimizer started ==="
            Restore-Services
            Write-Log "=== Optimization finished ==="
        }
    }
}

if ($Optimize) { Invoke-Action 'Optimize'; exit }
if ($Restore)  { Invoke-Action 'Restore';  exit }
if ($Verify)   { Invoke-VerifyConsole; exit }
if ($List)     { Show-List; exit }

while ($true) {
    Write-Host ''
    Write-Host '=== Windows Services Optimizer ===' -ForegroundColor White
    Write-Host '   1) Optimize (safe list)'
    Write-Host '   2) Optimize + optional list'
    Write-Host '   3) Restore (undo everything)'
    Write-Host '   4) Verify (check the result)'
    Write-Host '   5) Show service lists'
    Write-Host '   Q) Quit'
    $choice = Read-Host 'Choose an option'
    switch ($choice.Trim().ToUpper()) {
        '1' { Invoke-Action 'Optimize'; Read-Host "`nPress Enter to continue..." }
        '2' { $script:IncludeOptional = $true; Invoke-Action 'Optimize'; Read-Host "`nPress Enter to continue..." }
        '3' { Invoke-Action 'Restore'; Read-Host "`nPress Enter to continue..." }
        '4' { Invoke-VerifyConsole; Read-Host "`nPress Enter to continue..." }
        '5' { Show-List; Read-Host "`nPress Enter to continue..." }
        'Q' { exit }
        default { Write-Host 'Invalid choice.' -ForegroundColor Yellow }
    }
}
