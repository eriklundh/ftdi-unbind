<#
.SYNOPSIS
    Report Smart App Control state and (optionally) whether a path has
    a Windows Defender real-time scan exclusion.
.PARAMETER Path
    Folder path to check against the Defender exclusion list.
    Omit to skip the exclusion check.
.EXAMPLE
    .\scripts\check-dev-security.ps1
    .\scripts\check-dev-security.ps1 C:\usr\local\src
#>
param([string]$Path = '')

# Smart App Control state (Windows 11 only; stored in CI policy registry key)
$sacKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy'
try {
    $v = (Get-ItemProperty -Path $sacKey -Name VerifiedAndReputablePolicyState -ErrorAction Stop).VerifiedAndReputablePolicyState
    $label = switch ($v) {
        0 { 'Off' }
        1 { 'Evaluating' }
        2 { 'On' }
        default { "Unknown ($v)" }
    }
} catch {
    $label = 'Not present (Windows 10, or key inaccessible without elevation)'
}
Write-Host "Smart App Control : $label"

# Defender exclusion check
if ($Path) {
    $abs = (Resolve-Path -Path $Path -ErrorAction SilentlyContinue)?.Path
    if (-not $abs) { $abs = $Path }   # use as-is if path doesn't exist yet
    $excls = (Get-MpPreference -ErrorAction SilentlyContinue).ExclusionPath
    $found = $excls | Where-Object { $_ -ieq $abs }
    if ($found) {
        Write-Host "Defender exclusion : YES  $abs"
    } else {
        Write-Host "Defender exclusion : NO   $abs"
    }
}
