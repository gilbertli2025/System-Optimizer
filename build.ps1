<#
.SYNOPSIS
  Builds the System Optimizer apps: compiles the PowerShell sources to .exe
  with PS2EXE, signs them with your code-signing certificate, and builds the
  .msi installers with WiX v3.

.DESCRIPTION
  Requires:
    - PS2EXE module (https://github.com/MScholtes/PS2EXE)
    - WiX Toolset v3 binaries (candle.exe, light.exe)
  Adjust the paths below for your machine. Set $SignThumbprint to your
  code-signing certificate thumbprint, or $null to skip signing.

.EXAMPLE
  .\build.ps1
#>

# ---- config (edit these) ----
$ps2exeModule = 'C:\Users\admin\AppData\Local\Temp\opencode\ps2exe\PS2EXE-master\Module\ps2exe.psm1'
$wixBin       = 'C:\Users\admin\AppData\Local\Temp\opencode\wix\bin'
$outDir       = 'C:\Users\admin\Desktop\System-Optimizer'
$wxsDir       = 'C:\Users\admin\Desktop\System-Optimizer\source'
$SignThumbprint = 'C2DD93EC094DEAD52F7C275007B646452A9D79A6'  # set $null to skip signing
$TimeStampServer = 'http://timestamp.digicert.com'
# ---------------------------

$ErrorActionPreference = 'Stop'

function Invoke-Sign {
    param([string]$path)
    if (-not $SignThumbprint) { Write-Host "  (signing skipped)" -ForegroundColor DarkGray; return }
    $cert = Get-ChildItem "Cert:\CurrentUser\My\$SignThumbprint"
    Set-AuthenticodeSignature -FilePath $path -Certificate $cert -TimeStampServer $TimeStampServer -ErrorAction Stop | Out-Null
    $st = (Get-AuthenticodeSignature $path).Status
    Write-Host "  signed -> $st" -ForegroundColor Green
}

function Invoke-MSI {
    param([string]$wxsFile, [string]$msiName)
    $wixobj = Join-Path $env:TEMP ($wxsFile + '.wixobj')
    & (Join-Path $wixBin 'candle.exe') (Join-Path $wxsDir $wxsFile) -o $wixobj | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "candle failed: $wxsFile" }
    $msi = Join-Path $outDir $msiName
    & (Join-Path $wixBin 'light.exe') $wixobj -o $msi | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "light failed: $msiName" }
    Write-Host "  MSI built: $msi" -ForegroundColor Green
    Invoke-Sign $msi
}

Write-Host "=== Building System Optimizer ===" -ForegroundColor Cyan

if (Test-Path $ps2exeModule) { Import-Module $ps2exeModule -Force } else { Write-Warning "PS2EXE module not found at $ps2exeModule - skipping exe builds." }

# 1. Unified GUI app
if (Test-Path $ps2exeModule) {
    ps2exe -inputFile (Join-Path $wxsDir 'SystemOptimizer-GUI.ps1') -outputFile (Join-Path $outDir 'SystemOptimizer.exe') -title 'System Optimizer' -noConsole *> $null
    Write-Host "  compiled SystemOptimizer.exe" -ForegroundColor Green
    Invoke-Sign (Join-Path $outDir 'SystemOptimizer.exe')
}

# 2. MSI installers
if (Test-Path (Join-Path $wixBin 'candle.exe')) {
    Invoke-MSI 'SystemOptimizer.wxs'            'System-Optimizer.msi'
    Invoke-MSI 'WindowsServicesOptimizer.wxs'   'Windows-Services-Optimizer.msi'
    Invoke-MSI 'WindowsSecurityOptimizer.wxs'   'Windows-Security-Optimizer.msi'
} else {
    Write-Warning "WiX not found at $wixBin - skipping MSI builds."
}

Write-Host "=== Done ===" -ForegroundColor Cyan
