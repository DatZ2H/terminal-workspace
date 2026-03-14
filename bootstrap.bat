@echo off
:: Terminal Workspace Bootstrap Launcher
:: Bypasses ExecutionPolicy and launches bootstrap.ps1 in the best available PowerShell

where pwsh >nul 2>&1
if %errorlevel% equ 0 (
    echo   Launching bootstrap in PowerShell 7...
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0bootstrap.ps1" %*
    exit /b %errorlevel%
)

echo   PowerShell 7 not found — using Windows PowerShell...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bootstrap.ps1" %*
exit /b %errorlevel%
