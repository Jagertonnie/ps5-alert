@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ps5-alert.ps1" -Test
echo.
pause
