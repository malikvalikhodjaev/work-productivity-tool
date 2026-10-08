@echo off
powershell.exe -NoProfile -File "%~dp0Start-Dashboard.ps1" -NoBrowser
if errorlevel 1 exit /b 1
start "" "http://127.0.0.1:8787/alphas"
