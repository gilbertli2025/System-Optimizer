<#
.SYNOPSIS
  Windows Security Optimizer - console edition (thin shim). Real logic lives
  in lib/*.ps1.

.DESCRIPTION
  6 of the 10 security items (the "safe six"). Use the unified SystemOptimizer
  GUI for the additional hardening items (BitLocker, AutoRun, lockout,
  Office macros + WSH).

.EXAMPLE
  Windows-Security-Optimizer.exe                # interactive menu
  Windows-Security-Optimizer.exe -Harden        # apply hardening
  Windows-Security-Optimizer.exe -Restore       # undo hardening
  Windows-Security-Optimizer.exe -Review        # full security audit
#>
[CmdletBinding()]
param(
    [switch]$Harden,
    [switch]$Restore,
    [switch]$Review
)

$ErrorActionPreference = 'Stop'

$ScriptRoot = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { (Get-Location).Path }
. (Join-Path $ScriptRoot 'lib\Common.ps1')
. (Join-Path $ScriptRoot 'lib\SecurityItems.ps1')
. (Join-Path $ScriptRoot 'lib\Review.ps1')

$script:LogFile        = $script:Paths.SecurityLog
$script:LogMirrorHost  = $true

function Apply-Harden {
    Write-Log '=== Security Optimizer started ==='
    foreach ($id in 'cloud','firewall','scan','lock','browsers','restore') {
        Apply-SecurityItem -Id $id
    }
    Write-Log '=== Security Optimizer finished ==='
    Write-Host "`nDone. Backup at $($script:Paths.SecurityBackupFile). To undo, run with -Restore." -ForegroundColor Green
}

function Invoke-Restore {
    Restore-Security
    Write-Host "`nRestore complete." -ForegroundColor Green
}

function Invoke-ReviewConsole {
    Save-SecurityReview -Full
    Write-Host '' -ForegroundColor Green
    Write-Host ("Report saved to: " + $script:Paths.SecurityReviewFile) -ForegroundColor Cyan
}

function Restart-AdminConsole {
    param([string[]]$switches)
    Write-Host 'Requesting administrator privileges...' -ForegroundColor Yellow
    Restart-Admin -Arguments $switches
}

if ($Harden) {
    if (-not (Test-Admin)) { Restart-AdminConsole @('-Harden') }
    Apply-Harden; exit
}
if ($Restore) {
    if (-not (Test-Admin)) { Restart-AdminConsole @('-Restore') }
    Invoke-Restore; exit
}
if ($Review) { Invoke-ReviewConsole; exit }

while ($true) {
    Write-Host ''
    Write-Host '=== Windows Security Optimizer ===' -ForegroundColor White
    Write-Host '   1) Apply hardening (recommended)'
    Write-Host '   2) Restore (undo hardening)'
    Write-Host '   3) Security review'
    Write-Host '   Q) Quit'
    $choice = Read-Host 'Choose an option'
    switch ($choice.Trim().ToUpper()) {
        '1' { if (-not (Test-Admin)) { Restart-AdminConsole @('-Harden') } else { Apply-Harden }; Read-Host "`nPress Enter to continue..." }
        '2' { if (-not (Test-Admin)) { Restart-AdminConsole @('-Restore') } else { Invoke-Restore }; Read-Host "`nPress Enter to continue..." }
        '3' { Invoke-ReviewConsole; Read-Host "`nPress Enter to continue..." }
        'Q' { exit }
        default { Write-Host 'Invalid choice.' -ForegroundColor Yellow }
    }
}
