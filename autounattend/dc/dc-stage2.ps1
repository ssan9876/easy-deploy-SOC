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
$WeakSvc   = '@@WEAK_SVC_PASSWORD@@'   # deliberately weak, crackable service-account pw
$Upstream  = '@@UPSTREAM_DNS@@'
$DcHost    = $env:COMPUTERNAME

# Wait for AD web services to come up after the promotion reboot.
$dn = ($Domain.Split('.') | ForEach-Object { "DC=$_" }) -join ','
for ($i=0; $i -lt 30; $i++) {
    try { Import-Module ActiveDirectory -ErrorAction Stop; Get-ADDomain -ErrorAction Stop | Out-Null; break }
    catch { Start-Sleep 10 }
}

# Forward internet lookups upstream so domain members (using the DC for DNS) can
# still resolve external names for updates / agent downloads.
try {
    if (-not (Get-DnsServerForwarder).IPAddress) {
        Add-DnsServerForwarder -IPAddress $Upstream -ErrorAction Stop
        Write-Host "Added DNS forwarder -> $Upstream"
    }
} catch { Write-Warning "Could not set DNS forwarder: $_" }

# --- Lab OUs and users -------------------------------------------------------
$ouLab = "OU=SOCLab,$dn"
if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ouLab'" -ErrorAction SilentlyContinue)) {
    New-ADOrganizationalUnit -Name 'SOCLab' -Path $dn -ProtectedFromAccidentalDeletion $false
}

# Planted weaknesses for the hands-on labs (see docs/LEARNING.md, labs/):
#   helpdesk -> Domain Admins (privilege-escalation / lateral-movement target)
#   svc_sql  -> has an SPN + a weak password (Kerberoasting target that cracks)
$users = @(
    @{ sam='jsmith';  name='John Smith';  admin=$false; pass=$UserPass; spn=$null },
    @{ sam='awong';   name='Alice Wong';  admin=$false; pass=$UserPass; spn=$null },
    @{ sam='svc_sql'; name='SQL Service'; admin=$false; pass=$WeakSvc;
       spn="MSSQLSvc/$DcHost.$Domain:1433" },
    @{ sam='helpdesk';name='Help Desk';   admin=$true;  pass=$UserPass; spn=$null }
)
foreach ($u in $users) {
    if (-not (Get-ADUser -Filter "SamAccountName -eq '$($u.sam)'" -ErrorAction SilentlyContinue)) {
        $sec = ConvertTo-SecureString $u.pass -AsPlainText -Force
        New-ADUser -SamAccountName $u.sam -Name $u.name `
            -AccountPassword $sec -Enabled $true `
            -PasswordNeverExpires $true -Path $ouLab `
            -UserPrincipalName "$($u.sam)@$Domain"
        if ($u.admin) { Add-ADGroupMember -Identity 'Domain Admins' -Members $u.sam }
        if ($u.spn)   { Set-ADUser -Identity $u.sam -ServicePrincipalNames @{Add=$u.spn} }
        Write-Host "Created user $($u.sam)$(if($u.spn){" with SPN $($u.spn)"})"
    }
}

# --- Endpoint telemetry (Sysmon + Wazuh agent) -------------------------------
if (Test-Path 'C:\provision\install-agents.ps1') {
    & C:\provision\install-agents.ps1 -SiemIP $SiemIP -AgentName 'soc-dc01'
}

Stop-Transcript | Out-Null
