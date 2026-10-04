@echo off
title QuestBank Uploader setup
if not exist "%~dp0QuestBank-Uploader.ps1" goto missing
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0QuestBank-Uploader.ps1" -Install
if errorlevel 1 pause
exit /b

:missing
echo.
echo   QuestBank-Uploader.ps1 is not next to this file. Windows opened Install.bat
echo   straight from the zip: right-click the zip, pick Extract All, then run
echo   Install.bat from the extracted QuestBank Uploader folder.
echo.
pause
exit /b 1
