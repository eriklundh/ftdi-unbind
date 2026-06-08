@echo off
REM ███  THE BIG RED BUTTON  ███
REM Double-click to build + test + SIGN + package the three Windows tools.
REM Output lands in dist\. Pass-through args work too, e.g.:
REM   RELEASE.cmd -SkipTests
REM   RELEASE.cmd -Version v0.2.0
REM The window stays open at the end so you can read the result.
cd /d "%~dp0"
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\release-local.ps1" %*
echo.
pause
