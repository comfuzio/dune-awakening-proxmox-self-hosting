@echo off
if exist "%~dp0.internal" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0internal-scripts\initial-setup-internal.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0internal-scripts\initial-setup.ps1"
)
pause
