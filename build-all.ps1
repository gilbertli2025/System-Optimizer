# Build everything (PS2EXE -> .exe; WiX -> .msi) into $outRoot/System-Optimizer-v1.3.0/.
# Then writes a portable-friendly folder layout + 'run.bat' batch launcher.

$ErrorActionPreference = 'Stop'

$root    = Split-Path -Parent $PSCommandPath
$ps2exe  = Join-Path $root 'PS2EXE-master\Module\ps2exe.psm1'
$wix     = Join-Path $env:USERPROFILE 'Tools\wix314'

$outRoot = Join-Path $env:USERPROFILE 'Desktop\System-Optimizer-Build'
$stage   = Join-Path $outRoot 'System-Optimizer-v1.3.0'

# Wipe the stage if possible, otherwise overwrite files in place. If files
# in an older build are locked by a running process (e.g. the user is still
# testing SystemOptimizer.exe), we can't Remove-Item -Force them, but the
# downstream Copy-Item / Compress-Archive / candle / light calls will still
# overwrite each file with fresh content.
if (Test-Path $stage) {
    try { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction Stop }
    catch {
        Write-Host ("[warn] Could not wipe $stage - some files may be locked. Continuing with in-place overwrite.") -ForegroundColor Yellow
    }
}
New-Item -ItemType Directory -Path $stage -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stage 'lib') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stage 'portable') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stage 'installer') -Force | Out-Null

$version = '1.3.0'

# --------------------------------------------------------------------------
# Phase 1 - compile .ps1 -> .exe
# --------------------------------------------------------------------------
Write-Host '=== Compiling exes with PS2EXE ===' -ForegroundColor Cyan
Import-Module $ps2exe -Force

$guiParams = @{
    NoConsole    = $true
    requireAdmin = $true
    Version      = $version
    Description  = 'System Optimizer'
    Company      = 'System Optimizer'
    Product      = 'System Optimizer'
    Copyright    = 'MIT'
    ErrorAction  = 'Stop'
}
$consoleParams = $guiParams.Clone()
$consoleParams.NoConsole    = $false
$consoleParams.Description = 'System Optimizer (console)'

Invoke-ps2exe @guiParams    -inputFile (Join-Path $root 'SystemOptimizer-GUI.ps1')     -outputFile (Join-Path $stage 'SystemOptimizer.exe')           -title 'System Optimizer'                    | Out-Null
Invoke-ps2exe @guiParams    -inputFile (Join-Path $root 'WinServiceOptimizer-GUI.ps1')  -outputFile (Join-Path $stage 'WinServiceOptimizer-GUI.exe')   -title 'Windows Services Optimizer'           | Out-Null
Invoke-ps2exe @guiParams    -inputFile (Join-Path $root 'WinSecurityOptimizer-GUI.ps1') -outputFile (Join-Path $stage 'WinSecurityOptimizer-GUI.exe')  -title 'Windows Security Optimizer'           | Out-Null
Invoke-ps2exe @consoleParams -inputFile (Join-Path $root 'WinServiceOptimizer.ps1')    -outputFile (Join-Path $stage 'Windows-Services-Optimizer.exe') -title 'Windows Services Optimizer (console)' | Out-Null
Invoke-ps2exe @consoleParams -inputFile (Join-Path $root 'WinSecurityOptimizer.ps1')   -outputFile (Join-Path $stage 'Windows-Security-Optimizer.exe') -title 'Windows Security Optimizer (console)' | Out-Null

Write-Host '  compiled 5 exes' -ForegroundColor Green

# Copy lib/ + .ps1 sources (fallback if exe missing) + support files
$libDest = Join-Path $stage 'lib'
foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $root 'lib') -File)) {
    $destPath = Join-Path $libDest $f.Name
    Copy-Item -LiteralPath $f.FullName -Destination $destPath -Force
}
$support = @(
    'SystemOptimizer-GUI.ps1',
    'WinServiceOptimizer-GUI.ps1',
    'WinServiceOptimizer.ps1',
    'WinSecurityOptimizer-GUI.ps1',
    'WinSecurityOptimizer.ps1',
    '1-Click-System-Optimizer.cmd',
    'HELP.md','README.md','LICENSE','STEPS-for-end-users.txt'
)
foreach ($f in $support) {
    if (Test-Path -LiteralPath (Join-Path $root $f)) { Copy-Item -LiteralPath (Join-Path $root $f) -Destination $stage -Force }
}

# --------------------------------------------------------------------------
# Phase 2 - code-sign (timestamped) so Smart App Control accepts them
# --------------------------------------------------------------------------
Write-Host ''
Write-Host '=== Signing exes ===' -ForegroundColor Cyan
$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue
if (-not $cert) {
    Write-Host '  creating self-signed cert (one-off)' -ForegroundColor Yellow
    $cert = New-SelfSignedCertificate -Type 'CodeSigningCert' -Subject 'CN=System Optimizer (self-signed)' -CertStoreLocation 'Cert:\CurrentUser\My' -NotAfter (Get-Date).AddYears(2)
}
$tsUrl  = 'http://timestamp.digicert.com'
$cerOut = Join-Path $stage 'WSO-Trust.cer'
foreach ($exe in (Get-ChildItem -LiteralPath $stage -Filter '*.exe')) {
    Write-Host "  sign $($exe.Name)"
    $signed = $false
    try {
        Set-AuthenticodeSignature -FilePath $exe.FullName -Certificate $cert -TimestampServer $tsUrl -ErrorAction Stop | Out-Null
        $signed = $true
    } catch {
        try {
            Set-AuthenticodeSignature -FilePath $exe.FullName -Certificate $cert -ErrorAction Stop | Out-Null
            $signed = $true
        } catch {
            Write-Host "    [warn] could not sign (file may be locked by a running process): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}
Export-Certificate -Cert $cert -FilePath $cerOut | Out-Null
Write-Host "  -> $cerOut"

# --------------------------------------------------------------------------
# Phase 3 - build MSIs with WiX
# --------------------------------------------------------------------------
Write-Host ''
Write-Host '=== Building MSIs with WiX ===' -ForegroundColor Cyan
$candle = Join-Path $wix 'candle.exe'
$light  = Join-Path $wix 'light.exe'

if (-not (Test-Path $candle)) {
    Write-Host "  WiX not found at $candle - SKIPPING MSI build." -ForegroundColor Yellow
} else {
    # Build the 3 MSIs into the portable folder for easy testing
    $msiDir = Join-Path $stage 'installer'
    foreach ($wxs in 'SystemOptimizer.wxs','WindowsServicesOptimizer.wxs','WindowsSecurityOptimizer.wxs') {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($wxs)
        $wixobj = Join-Path $env:TEMP "$name.wixobj"
        Write-Host "  candle $wxs"
        & $candle "-dSourceDir=$stage" "-dVersion=$version" (Join-Path $root $wxs) "-out" $wixobj | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "candle failed: $wxs" }
        $msi = Join-Path $msiDir ($name + '.msi')
        Write-Host "  light  -> $msi"
        & $light $wixobj "-out" $msi | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "light failed: $name" }
        # Remove the WiX debug pdb (not needed at install time)
        $pdb = Join-Path $msiDir ($name + '.wixpdb')
        if (Test-Path -LiteralPath $pdb) { Remove-Item -LiteralPath $pdb -Force }
    }
}

# --------------------------------------------------------------------------
# Phase 4 - write the run.bat batch launcher and a portable sub-folder
# --------------------------------------------------------------------------
Write-Host ''
Write-Host '=== Writing run.bat and portable launcher ===' -ForegroundColor Cyan

# The 'portable' subfolder is a SELF-CONTAINED copy that needs no installer.
$portableDir = Join-Path $stage 'portable'
foreach ($item in (Get-ChildItem -LiteralPath $stage)) {
    if ($item.Name -eq 'portable' -or $item.Name -eq 'installer') { continue }
    if ($item.PSIsContainer) {
        Copy-Item -LiteralPath $item.FullName -Destination $portableDir -Recurse -Force
    } else {
        Copy-Item -LiteralPath $item.FullName -Destination $portableDir -Force
    }
}

$runBat = @"
@echo off
setlocal EnableExtensions
title System Optimizer
cd /d "%~dp0"

rem ============================================================================
rem Launch the .ps1 source via PowerShell with -ExecutionPolicy Bypass.
rem This works on every PC regardless of the system execution policy.
rem The .exe files are bundled but only used as a fallback / convenience.
rem ============================================================================

powershell -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0SystemOptimizer-GUI.ps1"

echo.
echo --- System Optimizer finished (the window closed). ---
echo.
echo Useful commands you can run from this folder:
echo.
echo   run.bat                              : launch the unified GUI (this file)
echo   apply-services.bat                   : apply recommended services (admin)
echo   apply-security.bat                    : apply security hardening  (admin)
echo   verify-services.bat                  : verify services                (admin)
echo   review-security.bat                  : print security review          (admin)
echo   restore-services.bat                 : revert services                (admin)
echo   restore-security.bat                 : revert security                 (admin)
echo.
echo To install via MSI instead, copy the installer\*.msi to the target PC
echo and double-click it.
echo.
pause
exit /b 0
"@
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
function Write-TextNoBom([string]$path, [string]$content) {
    [System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
}

Write-TextNoBom (Join-Path $stage 'run.bat') $runBat
Copy-Item -LiteralPath (Join-Path $stage 'run.bat') -Destination (Join-Path $stage 'portable\run.bat') -Force

# Wrap a smaller batch file just for the portable subfolder
$portableBat = @"
@echo off
setlocal EnableExtensions
title System Optimizer (Portable)
cd /d "%~dp0"
echo This is the PORTABLE folder. To switch to the full package (with installer
echo files), go up one level and run run.bat from the parent folder.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0SystemOptimizer-GUI.ps1"
exit /b 0
"@
Write-TextNoBom (Join-Path $stage 'portable\launch.bat') $portableBat $portableBat

# Helper batch files - one per common action.
$helpers = [ordered]@{
    'apply-services.bat'    = 'powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0WinServiceOptimizer.ps1" -Optimize'
    'apply-security.bat'    = 'powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0WinSecurityOptimizer.ps1" -Harden'
    'restore-services.bat'  = 'powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0WinServiceOptimizer.ps1" -Restore'
    'restore-security.bat'  = 'powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0WinSecurityOptimizer.ps1" -Restore'
    'verify-services.bat'   = 'powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0WinServiceOptimizer.ps1" -Verify'
    'review-security.bat'   = 'powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0WinSecurityOptimizer.ps1" -Review'
    'list-services.bat'     = 'powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0WinServiceOptimizer.ps1" -List'
}
foreach ($name in $helpers.Keys) {
    $cmd = $helpers[$name]
    $content = "@echo off`r`nsetlocal`r`ntitle $name`r`ncd /d `"%~dp0`"`r`necho Starting $name ...`r`n$cmd`r`nexit /b 0`r`n"
    Write-TextNoBom (Join-Path $stage $name) $content
    Write-TextNoBom (Join-Path (Join-Path $stage 'portable') $name) $content
}
Write-Host '  added run.bat + 7 helper batch files'
Write-Host '  added run.bat + 7 helper batch files'


# A small build-msi.ps1 so the user can rebuild MSIs on another machine without re-running PS2EXE
$buildMsiPs1 = @"
# Rebuild MSIs from the contents of this folder (exe + lib). Requires
# WiX 3.x installed and on PATH (or set `$wixBin = '<path>'` below).
`$ErrorActionPreference = 'Stop'
`$root   = Split-Path -Parent `$PSCommandPath
`$wixBin = `$env:WSO_WIX
if (-not `$wixBin) { `$wixBin = 'C:\Program Files (x86)\WiX Toolset v3.11\bin' }
if (-not (Test-Path (Join-Path `$wixBin 'candle.exe'))) {
    Write-Host "WiX candle.exe not found at `$wixBin . Set `$env:WSO_WIX or update this script." -ForegroundColor Yellow
    exit 1
}
`$version = '1.3.0'
foreach (`$wxs in 'SystemOptimizer.wxs','WindowsServicesOptimizer.wxs','WindowsSecurityOptimizer.wxs') {
    `$name = [System.IO.Path]::GetFileNameWithoutExtension(`$wxs)
    `$wixobj = Join-Path `$env:TEMP "`$name.wixobj"
    & (Join-Path `$wixBin 'candle.exe') "-dSourceDir=`$root" "-dVersion=`$version" (Join-Path `$root `$wxs) '-out' `$wixobj | Out-Null
    if (`$LASTEXITCODE -ne 0) { throw "candle failed: `$wxs" }
    & (Join-Path `$wixBin 'light.exe') `$wixobj '-out' (Join-Path `$root 'installer' "`$name.msi") | Out-Null
    if (`$LASTEXITCODE -ne 0) { throw "light failed: `$name" }
    Write-Host "Built: `$name.msi" -ForegroundColor Green
}
Write-Host 'MSIs written to installer subfolder.' -ForegroundColor Green
"@
Write-TextNoBom (Join-Path $stage 'build-msi.ps1') $buildMsiPs1

# Update INSTALL.txt so it points at run.bat as well
$installText = @"
System Optimizer v1.3.0 - QUICK TEST GUIDE
==========================================
THIS FOLDER
-----------
  run.bat                           Double-click this to launch the unified GUI.
                                    (or just run SystemOptimizer.exe directly)
  SystemOptimizer.exe               Unified GUI - Performance, Security,
                                    Maintenance, Repair - all in one window.
  WinServiceOptimizer-GUI.exe       Services-only GUI.
  WinSecurityOptimizer-GUI.exe      Security-only GUI.
  Windows-Services-Optimizer.exe    Console (command-line) services tool.
  Windows-Security-Optimizer.exe    Console (command-line) security tool.

  *.ps1 (sources)                   Same as above but in PowerShell - used
                                    automatically as a fallback if the .exe
                                    is missing.

  WSO-Trust.cer                     Self-signed code-signing certificate.
                                    Run via 1-Click-System-Optimizer.cmd to
                                    install and trust.

  lib\*.ps1                        Shared library used by every entry point.
  HELP.md, README.md, LICENSE, STEPS-for-end-users.txt
                                    Documentation.

  installer\*.msi                   MSI installers built by WiX for per-PC
                                    installation via Add/Remove Programs.
                                    Run build-msi.ps1 to rebuild them.

  portable\                         Self-contained subfolder - same files,
                                    just duplicated so you can copy it as a
                                    single folder anywhere.

  build-msi.ps1                     Rebuilds the MSIs in this folder from
                                    the contents already here (no PS2EXE
                                    required; only needs WiX 3.x).


HOW TO TEST ON ANOTHER PC
-------------------------
  Fastest path - copy the whole folder:
      1. Copy the whole System-Optimizer-v1.3.0\ folder to the target PC
         (e.g. to C:\Tools\ on the target PC).
      2. On the target PC, RIGHT-CLICK run.bat  -->  Run as administrator.
      3. The unified GUI opens. Tick what you want, click Apply ALL
         selected, then reboot.

  Clean path - install via MSI:
      1. Copy installer\System-Optimizer.msi to the target PC.
      2. Double-click to install (also installs to Start Menu).
      3. Launch from Start Menu: System Optimizer.

  Portable path - use the portable\ subfolder as a stick-on / USB setup:
      1. Copy portable\ to a USB stick.
      2. Plug into the target PC.
      3. Double-click run.bat (or launch.bat in the portable subfolder).


WHAT CAN GO WRONG (AND THE FIX)
-------------------------------
  "Windows protected your PC" (Win10 SmartScreen)
      -> Click "More info" then "Run anyway".

  Smart App Control blocks the .exe (Win11)
      -> Either run 1-Click-System-Optimizer.cmd (it installs WSO-Trust.cer),
         or turn Smart App Control off in Windows Security.

  Access denied when applying changes
      -> You forgot Run as administrator. Right-click run.bat and pick again.

  Something looks blurry
      -> Right-click SystemOptimizer.exe  -> Properties  -> Compatibility
         -> Change high DPI settings  -> Override high DPI scaling  -> System.

  Want to roll everything back to defaults
      -> Re-run run.bat, in the GUI click "Restore ALL to defaults", reboot.

  Want to rebuild the MSIs from source
      -> Open PowerShell, cd into this folder, run:  powershell .\build-msi.ps1


LICENSE
-------
MIT. No warranty. Test on a non-critical PC first.
"@
Write-TextNoBom (Join-Path $stage 'INSTALL.txt') $installText
Copy-Item -LiteralPath (Join-Path $stage 'INSTALL.txt') -Destination (Join-Path $stage 'portable\INSTALL.txt') -Force

# --------------------------------------------------------------------------
# Final: tree summary + size
# --------------------------------------------------------------------------
Write-Host ''
Write-Host '=== Final layout ===' -ForegroundColor Cyan
Get-ChildItem -LiteralPath $stage -Recurse -File | ForEach-Object {
    $rel  = $_.FullName.Substring($stage.Length + 1)
    $relP = ($rel -split '\\')[0]
    $sz   = ('{0,9:N0}B' -f $_.Length)
    Write-Host ("  {0}  {1}" -f $sz, $rel)
}

$totalBytes = (Get-ChildItem -LiteralPath $stage -Recurse -File | Measure-Object -Property Length -Sum).Sum
$totalCount = (Get-ChildItem -LiteralPath $stage -Recurse -File).Count
Write-Host ''
Write-Host ("  Total: {0} files, {1:N0} bytes ({2:N1} KB)" -f $totalCount, $totalBytes, ($totalBytes / 1KB)) -ForegroundColor Green
Write-Host ''
Write-Host "Output: $stage" -ForegroundColor Green
Write-Host ''
Write-Host ('  Portable copy (no installer files): {0}\portable\run.bat' -f $stage)
Write-Host ('  MSI installers:                     {0}\installer\*.msi' -f $stage)
Write-Host ''
