@echo off
setlocal
title System Optimizer Launcher
cd /d "%~dp0"

rem --- Elevate if not already admin ---
net session >nul 2>&1
if not %errorlevel%==0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

rem --- Install the signing certificate once (so signed exes are trusted) ---
if exist "%~dp0WSO-Trust.cer" (
    certutil -addstore -f Root "%~dp0WSO-Trust.cer" >nul 2>&1
)

rem --- Check if running from a USB (removable) drive ---
set DTYPE=
for /f "tokens=2 delims==" %%a in ('wmic logicaldisk where "DeviceID='%~d0'" get DriveType /value 2^>nul ^| find "="') do set DTYPE=%%a
if /I "%DTYPE%"=="2" (
    echo.
    echo Running from a USB drive - good.
) else (
    echo.
    echo NOTE: Best practice is to run this tool from a USB drive and keep your
    echo settings backup there. You can continue from here.
    echo Remember: use the Backup ^& Restore tab to save your settings first.
    echo.
    pause
)

rem --- Start the app (PowerShell source, Bypass) ---
start "" powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0SystemOptimizer-GUI.ps1"
exit /b 0
