# Rebuild MSIs from the contents of this folder using WiX 3.x.
# Requires WiX candle.exe + light.exe on PATH or in `$wixBin`.
$ErrorActionPreference = 'Stop'
$root   = Split-Path -Parent $PSCommandPath
$wixBin = $env:WSO_WIX
if (-not $wixBin) { $wixBin = 'C:\Tools\wix314' }
if (-not (Test-Path (Join-Path $wixBin 'candle.exe'))) {
    Write-Host "WiX candle.exe not found at $wixBin . Set `$env:WSO_WIX or update this script." -ForegroundColor Yellow
    exit 1
}
$version = '1.3.0'
foreach ($wxs in 'SystemOptimizer.wxs','WindowsServicesOptimizer.wxs','WindowsSecurityOptimizer.wxs') {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($wxs)
    $wixobj = Join-Path $env:TEMP "$name.wixobj"
    & (Join-Path $wixBin 'candle.exe') "-dSourceDir=$root" "-dVersion=$version" (Join-Path $root $wxs) '-out' $wixobj | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "candle failed: $wxs" }
    & (Join-Path $wixBin 'light.exe') $wixobj '-out' (Join-Path $root 'installer' "$name.msi") | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "light failed: $name" }
    Write-Host "Built: $name.msi" -ForegroundColor Green
}
Write-Host 'MSIs written to installer subfolder.' -ForegroundColor Green
