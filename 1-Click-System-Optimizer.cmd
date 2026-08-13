@echo off
setlocal
title System Optimizer - One-click Installer

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
if not exist "%~dp0WSO-Trust.cer"      ( echo   MISSING: WSO-Trust.cer & set MISSING=1 )
if not exist "%~dp0SystemOptimizer.exe" ( echo   MISSING: SystemOptimizer.exe & set MISSING=1 )
if "%MISSING%"=="1" goto :missing

echo [1/2] Installing trusted certificate...
certutil -addstore -f Root "%~dp0WSO-Trust.cer"
if %errorlevel%==0 (
    echo       Certificate installed OK.
) else (
    echo       WARNING: certificate install failed, see message above.
)

echo [2/2] Starting System Optimizer...
start "" "%~dp0SystemOptimizer.exe"
echo       Done. The optimizer is starting...
timeout /t 2 /nobreak >nul
exit /b 0

:missing
echo.
echo   ERROR: Some files are missing from this folder.
echo   This file, WSO-Trust.cer and SystemOptimizer.exe must all be in the
echo   SAME folder. Copy the whole System-Optimizer folder or extract the
echo   whole ZIP, then run this .cmd again.
pause
exit /b 1
