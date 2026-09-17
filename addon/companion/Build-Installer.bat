@echo off
setlocal
title ForeverProbe installer build
rem Compiles "ForeverProbe Setup.exe" from Launcher.cs with the sigil icon
rem embedded. Needs nothing beyond Windows itself: csc.exe ships with the
rem .NET Framework. Run this on the Windows box, commit the exe, and
rem tools\build_companion.py bundles it at the zip root.

set "HERE=%~dp0"
set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%CSC%" (
  echo Could not find csc.exe under %WINDIR%\Microsoft.NET.
  echo The .NET Framework 4.x is part of Windows 10/11, so this is unusual.
  pause
  exit /b 1
)

"%CSC%" /nologo /target:winexe /win32icon:"%HERE%ForeverProbe.ico" /out:"%HERE%ForeverProbe Setup.exe" "%HERE%Launcher.cs"
if errorlevel 1 (
  echo Build failed.
  pause
  exit /b 1
)

echo Built: %HERE%ForeverProbe Setup.exe
echo Next: run tools\build_companion.py so the zip carries it at the root.
pause
