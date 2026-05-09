@echo off
if exist "%~dp0.internal" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0\internal-scripts\battlegroup-internal.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0\internal-scripts\battlegroup.ps1"
)
pause
