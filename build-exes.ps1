# Build System Optimizer with PS2EXE (already-extracted to ./PS2EXE-master/Module).
$ErrorActionPreference = 'Stop'

$root      = $PSScriptRoot
$ps2exeDir = Join-Path $root 'PS2EXE-master\Module'
$ps2exeMod = Join-Path $ps2exeDir 'ps2exe.psm1'

if (-not (Test-Path -LiteralPath $ps2exeMod)) {
    throw "PS2EXE module not found at $ps2exeMod. Please unzip PS2EXE-master.zip into $root."
}

$outDir = Join-Path $env:USERPROFILE 'Desktop\System-Optimizer'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

Import-Module $ps2exeMod -Force
Write-Host "PS2EXE loaded from $ps2exeDir" -ForegroundColor Green

$version = '1.3.0'
$ps2exeParams = @{
    NoConsole       = $true
    requireAdmin    = $true
    Version         = $version
    Description     = 'System Optimizer'
    Company         = 'System Optimizer'
    Product         = 'System Optimizer'
    Copyright       = 'MIT'
    ErrorAction     = 'Stop'
}

Write-Host 'Compiling exes...' -ForegroundColor Cyan

Invoke-ps2exe @ps2exeParams -inputFile (Join-Path $root 'SystemOptimizer-GUI.ps1')     -outputFile (Join-Path $outDir 'SystemOptimizer.exe')              -title 'System Optimizer'                  | Out-Null
Write-Host '  compiled SystemOptimizer.exe' -ForegroundColor Green

Invoke-ps2exe @ps2exeParams -inputFile (Join-Path $root 'WinServiceOptimizer-GUI.ps1')  -outputFile (Join-Path $outDir 'WinServiceOptimizer-GUI.exe')     -title 'Windows Services Optimizer'         | Out-Null
Write-Host '  compiled WinServiceOptimizer-GUI.exe' -ForegroundColor Green

Invoke-ps2exe @ps2exeParams -inputFile (Join-Path $root 'WinSecurityOptimizer-GUI.ps1') -outputFile (Join-Path $outDir 'WinSecurityOptimizer-GUI.exe')    -title 'Windows Security Optimizer'         | Out-Null
Write-Host '  compiled WinSecurityOptimizer-GUI.exe' -ForegroundColor Green

Write-Host 'Compiling console exes...' -ForegroundColor Cyan
$ps2exeConsole = @{
    NoConsole    = $false
    requireAdmin = $true
    Version      = $version
    Description  = 'System Optimizer (console)'
    Company      = 'System Optimizer'
    Product      = 'System Optimizer'
    Copyright    = 'MIT'
    ErrorAction  = 'Stop'
}

Invoke-ps2exe @ps2exeConsole -inputFile (Join-Path $root 'WinServiceOptimizer.ps1')    -outputFile (Join-Path $outDir 'Windows-Services-Optimizer.exe') -title 'Windows Services Optimizer (console)' | Out-Null
Write-Host '  compiled Windows-Services-Optimizer.exe' -ForegroundColor Green

Invoke-ps2exe @ps2exeConsole -inputFile (Join-Path $root 'WinSecurityOptimizer.ps1')   -outputFile (Join-Path $outDir 'Windows-Security-Optimizer.exe') -title 'Windows Security Optimizer (console)' | Out-Null
Write-Host '  compiled Windows-Security-Optimizer.exe' -ForegroundColor Green

# Copy all the supporting files so the installer is self-contained
Write-Host 'Copying support files...' -ForegroundColor Cyan
$libDest = Join-Path $outDir 'lib'
if (-not (Test-Path -LiteralPath $libDest)) { New-Item -ItemType Directory -Path $libDest -Force | Out-Null }
$support = @(
    '1-Click-System-Optimizer.cmd',
    'HELP.md','README.md','LICENSE','STEPS-for-end-users.txt',
    'INSTALL.txt'
)
foreach ($f in $support) {
    $srcPath = Join-Path $root $f
    if (Test-Path -LiteralPath $srcPath) { Copy-Item -LiteralPath $srcPath -Destination $outDir -Force }
}
foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $root 'lib') -File)) {
    $destPath = Join-Path $libDest $f.Name
    Copy-Item -LiteralPath $f.FullName -Destination $destPath -Force
}

Get-ChildItem -LiteralPath $outDir -Recurse | ForEach-Object {
    $rel = $_.FullName.Substring($outDir.Length + 1)
    $sz  = if ($_.PSIsContainer) { '  <DIR>' } else { ($_.Length.ToString('N0') + 'B').PadLeft(10) }
    Write-Host ("  {0}  {1}" -f $sz, $rel)
}

Write-Host ''
Write-Host "Done. Output: $outDir" -ForegroundColor Green
