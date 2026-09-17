@echo off
title ForeverProbe Sync removal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ForeverProbe-Sync.ps1" -Uninstall
pause
