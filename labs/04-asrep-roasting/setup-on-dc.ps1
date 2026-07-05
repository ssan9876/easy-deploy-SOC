<#
    setup-on-dc.ps1 — RUN THIS ON THE DC (as an admin) to create the condition
    for AS-REP roasting: an account with Kerberos pre-authentication disabled.
    This is the deliberate weakness the lab then exploits.

    Usage (on soc-dc01, PowerShell as admin):
        .\setup-on-dc.ps1               # targets 'jsmith' by default
        .\setup-on-dc.ps1 -Sam awong
#>
param([string]$Sam = 'jsmith')
Import-Module ActiveDirectory
Set-ADAccountControl -Identity $Sam -DoesNotRequirePreAuth $true
Write-Host "Disabled Kerberos pre-auth on '$Sam'. It is now AS-REP roastable."
Write-Host "Revert later with: Set-ADAccountControl -Identity $Sam -DoesNotRequirePreAuth `$false"
