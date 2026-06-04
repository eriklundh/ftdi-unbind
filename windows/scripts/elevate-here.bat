@echo off

:: 1. Check for Admin rights. If not elevated, restart via PowerShell and pass the current directory path.
fsutil dirty query %systemdrive% >nul 2>&1
if %errorLevel% neq 0 (
    echo Elevating privileges...
    powershell -Command "Start-Process cmd -ArgumentList '/k cd /d ""%cd%""' -Verb RunAs"
    exit /b
)

:: 2. Your batch file scripts/commands go below this line
echo Successfully running as Administrator in the same directory!
echo Current directory: %cd%

pause