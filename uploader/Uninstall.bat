@echo off
title QuestBank Uploader removal
if not exist "%~dp0QuestBank-Uploader.ps1" goto missing
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0QuestBank-Uploader.ps1" -Uninstall
pause
exit /b

:missing
echo.
echo   QuestBank-Uploader.ps1 is not next to this file. Extract the whole zip
echo   first, then run Uninstall.bat from the extracted folder.
echo.
pause
exit /b 1
