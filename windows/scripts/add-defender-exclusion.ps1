<#
.SYNOPSIS
    Add a folder path to the Windows Defender real-time scan exclusion list.
    Requires an elevated (Administrator) shell.
.PARAMETER Path
    Folder to exclude from real-time scanning.
.EXAMPLE
    .\scripts\add-defender-exclusion.ps1 C:\usr\local\src
#>
#Requires -RunAsAdministrator
param([Parameter(Mandatory)][string]$Path)

# Resolve to an absolute path if it already exists on disk; otherwise keep as-is.
$abs = (Resolve-Path -Path $Path -ErrorAction SilentlyContinue)?.Path
if (-not $abs) { $abs = $Path }

Add-MpPreference -ExclusionPath $abs
Write-Host "Defender exclusion added: $abs"
