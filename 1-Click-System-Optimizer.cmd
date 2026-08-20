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
for /f %%a in ('powershell -NoProfile -Command "$d = (Get-Location).Path.Substring(0,2); [System.IO.DriveInfo]::new($d).DriveType"') do set DTYPE=%%a
if /I "%DTYPE%"=="Removable" (
    echo.
    echo Running from a USB drive - good.
) else (
    echo.
    echo Please only run the System-Optimizer from a USB drive.
    echo This program will back up your user settings to the USB drive
    echo before running the optimizer.
    echo.
    pause
)

rem --- Start the app (PowerShell source, Bypass) ---
start "" powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0SystemOptimizer-GUI.ps1"
exit /b 0
