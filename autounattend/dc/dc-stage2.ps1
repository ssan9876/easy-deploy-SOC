<#
    dc-stage2.ps1 — runs once after the DC reboots and AD DS is live.
    Creates a small, deliberately-practiceable set of OUs and users, then
    installs Sysmon + the Wazuh agent so the DC ships telemetry to the SIEM.
#>
$ErrorActionPreference = 'Continue'
Start-Transcript -Path 'C:\provision\dc-stage2.log' -Append | Out-Null

$Domain    = '@@DOMAIN@@'
$SiemIP    = '@@SIEM_IP@@'
$UserPass  = '@@USERPASS@@'

# Wait for AD web services to come up after the promotion reboot.
$dn = ($Domain.Split('.') | ForEach-Object { "DC=$_" }) -join ','
for ($i=0; $i -lt 30; $i++) {
    try { Import-Module ActiveDirectory -ErrorAction Stop; Get-ADDomain -ErrorAction Stop | Out-Null; break }
    catch { Start-Sleep 10 }
}

# --- Lab OUs and users -------------------------------------------------------
$ouLab = "OU=SOCLab,$dn"
if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ouLab'" -ErrorAction SilentlyContinue)) {
    New-ADOrganizationalUnit -Name 'SOCLab' -Path $dn -ProtectedFromAccidentalDeletion $false
}

$sec = ConvertTo-SecureString $UserPass -AsPlainText -Force
$users = @(
    @{ sam='jsmith';  name='John Smith';   admin=$false },
    @{ sam='awong';   name='Alice Wong';   admin=$false },
    @{ sam='svc_sql'; name='SQL Service';  admin=$false },
    @{ sam='helpdesk';name='Help Desk';    admin=$true  }   # over-privileged on purpose
)
foreach ($u in $users) {
    if (-not (Get-ADUser -Filter "SamAccountName -eq '$($u.sam)'" -ErrorAction SilentlyContinue)) {
        New-ADUser -SamAccountName $u.sam -Name $u.name `
            -AccountPassword $sec -Enabled $true `
            -PasswordNeverExpires $true -Path $ouLab `
            -UserPrincipalName "$($u.sam)@$Domain"
        if ($u.admin) { Add-ADGroupMember -Identity 'Domain Admins' -Members $u.sam }
        Write-Host "Created user $($u.sam)"
    }
}

# --- Endpoint telemetry (Sysmon + Wazuh agent) -------------------------------
if (Test-Path 'C:\provision\install-agents.ps1') {
    & C:\provision\install-agents.ps1 -SiemIP $SiemIP -AgentName 'soc-dc01'
}

Stop-Transcript | Out-Null
