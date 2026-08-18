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

rem --- Start the app (PowerShell source, Bypass) ---
start "" powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0SystemOptimizer-GUI.ps1"
exit /b 0
