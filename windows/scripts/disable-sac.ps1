<#
.SYNOPSIS
    Turn Smart App Control off by writing to the CI policy registry key.
    Requires an elevated (Administrator) shell.

WARNING: Smart App Control cannot be re-enabled without resetting the PC.
         Only run this on a dedicated development machine.

If this script fails with an access-denied error, use the UI instead:
    Windows Security → App & browser control → Smart App Control settings → Off
#>
#Requires -RunAsAdministrator

$sacKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy'
Set-ItemProperty -Path $sacKey -Name VerifiedAndReputablePolicyState -Value 0 -Type DWord
Write-Host 'Smart App Control set to Off.  Reboot to ensure the change takes effect.'
