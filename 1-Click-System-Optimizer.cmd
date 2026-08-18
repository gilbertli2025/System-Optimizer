@echo off
setlocal
title System Optimizer - One-click Installer
cd /d "%~dp0"

rem --- Check for admin rights; if missing, relaunch elevated ---
net session >nul 2>&1
if not %errorlevel%==0 (
    echo Requesting administrator rights...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

rem --- Smart App Control notice (may block the tool) ---
for /f "tokens=3" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy" /v VerifiedAndReputablePolicyState 2^>nul') do set SACSTATE=%%a
if /I "%SACSTATE%"=="0x1" (
    echo.
    echo NOTE: Smart App Control is ON. This Windows 11 feature may block the tool.
    echo       To allow it: Windows Security ^> App ^& browser control ^> Smart App Control ^> Off
    echo       then reboot.
    echo.
)

echo.
echo Running from folder: %~dp0
echo.

rem --- Verify required files are present ---
set MISSING=0
if not exist "%~dp0SystemOptimizer-GUI.ps1" ( echo   MISSING: SystemOptimizer-GUI.ps1 & set MISSING=1 )
if not exist "%~dp0lib\Common.ps1"          ( echo   MISSING: lib\Common.ps1 & set MISSING=1 )
if "%MISSING%"=="1" goto :missing

rem --- Install the (self-signed) signing certificate so any signed .exe is trusted ---
if exist "%~dp0WSO-Trust.cer" (
    echo [1/2] Installing trusted certificate (only needs to run once per PC)...
    certutil -addstore -f Root "%~dp0WSO-Trust.cer" >nul
    if %errorlevel%==0 (
        echo       Certificate installed OK.
    ) else (
        echo       WARNING: certificate install failed.
    )
) else (
    echo [1/2] Skipping certificate install (WSO-Trust.cer not present).
)

echo [2/2] Starting System Optimizer (PowerShell source with Bypass)...
start "System Optimizer" powershell -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0SystemOptimizer-GUI.ps1"
echo       Started. The optimizer is opening in its own window.
timeout /t 2 /nobreak >nul
exit /b 0

:missing
echo.
echo   ERROR: Could not find SystemOptimizer-GUI.ps1 and/or lib\Common.ps1.
echo   Make sure this .cmd lives in the SAME folder as SystemOptimizer-GUI.ps1
echo   and the lib\ folder. Re-download from
echo     https://github.com/gilbertli2025/System-Optimizer/releases
pause
exit /b 1
