@echo off
:: diagnosis.cmd — run the FTDI diagnosis from a legacy Command Prompt (CMD).
:: Author Erik Lundh, The Joy of Engineering, erik.lundh@ingenjorsgladje.se
::
:: This is a thin wrapper.  The actual diagnostic work is done in PowerShell
:: by diagnosis.ps1, which lives in the same folder as this file.
::
:: Usage:
::   diagnosis.cmd              run the diagnosis (default VID:PID 0403:6015)
::   diagnosis.cmd 0403:6014    run against a specific VID:PID
::   diagnosis.cmd /?           show full help and about (also -? /h -h /help --help)
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

if "%~1"=="/?" goto :help
if /I "%~1"=="-?" goto :help
if /I "%~1"=="/h" goto :help
if /I "%~1"=="-h" goto :help
if /I "%~1"=="/help" goto :help
if /I "%~1"=="--help" goto :help

powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%PS1%" %*
exit /b %ERRORLEVEL%

:help
:: Render the comment-based help written in diagnosis.ps1 (.SYNOPSIS,
:: .DESCRIPTION, usage, examples, and the about/author block in .NOTES).
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "Get-Help -Full '%PS1%'"
exit /b %ERRORLEVEL%
