@echo off
:: diagnosis.cmd — run the FTDI diagnosis from a legacy Command Prompt (CMD).
:: Author Erik Lundh, The Joy of Engineering, erik.lundh@ingenjorsgladje.se
::
:: This is a thin wrapper.  The actual diagnostic work is done in PowerShell
:: by diagnosis.ps1, which lives in the same folder as this file.
::
:: If you already have a PowerShell window open, you can run directly:
::   .\diagnosis.ps1
::
:: Note: -ExecutionPolicy Bypass applies only to this one invocation.
::       It does not change your system's PowerShell execution policy.
::
setlocal

set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%diagnosis.ps1"

if not exist "%PS1%" (
    echo.
    echo  ERROR: diagnosis.ps1 was not found next to this file.
    echo  Expected location: %PS1%
    echo  Make sure diagnosis.cmd and diagnosis.ps1 are in the same folder.
    echo.
    pause
    exit /b 1
)

powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%PS1%" %*
exit /b %ERRORLEVEL%
