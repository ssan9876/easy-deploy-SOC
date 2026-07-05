<#
    join-domain.ps1 — runs at first logon on the Windows client.
    Sets static networking with the DC as DNS, waits for the DC to answer, joins
    the domain, installs endpoint agents, then reboots. Placeholders (@@NAME@@)
    are substituted by scripts/deploy-client.sh.
#>
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force 'C:\provision' | Out-Null
Start-Transcript -Path 'C:\provision\join-domain.log' -Append | Out-Null

$Domain   = '@@DOMAIN@@'
$IP       = '@@IP@@'
$Prefix   = @@PREFIX@@
$Gateway  = '@@GATEWAY@@'
$DcIP     = '@@DC_IP@@'
$SiemIP   = '@@SIEM_IP@@'
$AdminPw  = '@@ADMINPASS@@'
$AgentName= '@@HOSTNAME@@'

# --- VirtIO guest tools (if the ISO is attached) -----------------------------
try {
    $vg = Get-ChildItem -Path (Get-PSDrive -PSProvider FileSystem | ForEach-Object Root) `
            -Filter 'virtio-win-guest-tools.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($vg) { Start-Process $vg.FullName -ArgumentList '/install','/quiet','/norestart' -Wait }
} catch { Write-Warning "VirtIO tools install skipped: $_" }

# --- Static networking, DNS = DC --------------------------------------------
$if = Get-NetAdapter -Physical | Where-Object Status -eq 'Up' | Select-Object -First 1
if (-not $if) { $if = Get-NetAdapter -Physical | Select-Object -First 1 }
Get-NetIPAddress -InterfaceIndex $if.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -ne $IP } |
    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
Remove-NetRoute -InterfaceIndex $if.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
New-NetIPAddress -InterfaceIndex $if.ifIndex -IPAddress $IP -PrefixLength $Prefix `
    -DefaultGateway $Gateway -ErrorAction SilentlyContinue | Out-Null
Set-DnsClientServerAddress -InterfaceIndex $if.ifIndex -ServerAddresses $DcIP

# --- Wait for the DC, then join ---------------------------------------------
$joined = (Get-CimInstance Win32_ComputerSystem).PartOfDomain
if (-not $joined) {
    Write-Host "Waiting for DC $DcIP to answer for $Domain ..."
    $ok = $false
    for ($i=0; $i -lt 60; $i++) {
        if (Resolve-DnsName -Name $Domain -Server $DcIP -ErrorAction SilentlyContinue) { $ok=$true; break }
        Start-Sleep 15
    }
    if (-not $ok) { Write-Warning "DC not reachable yet; will still attempt join." }

    $sec  = ConvertTo-SecureString $AdminPw -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential("$Domain\Administrator", $sec)

    # Register agent install to run after the post-join reboot.
    if (Test-Path 'C:\provision\install-agents.ps1') {
        Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' `
            -Name 'SocAgents' `
            -Value "powershell.exe -ExecutionPolicy Bypass -NoProfile -File C:\provision\install-agents.ps1 -SiemIP $SiemIP -AgentName $AgentName"
    }

    for ($i=0; $i -lt 5; $i++) {
        try {
            Add-Computer -DomainName $Domain -Credential $cred -Force -ErrorAction Stop
            Write-Host "Joined $Domain. Rebooting."
            Restart-Computer -Force
            break
        } catch {
            Write-Warning "Join attempt $($i+1) failed: $_"
            Start-Sleep 20
        }
    }
} else {
    Write-Host "Already domain-joined."
    if (Test-Path 'C:\provision\install-agents.ps1') {
        & C:\provision\install-agents.ps1 -SiemIP $SiemIP -AgentName $AgentName
    }
}

Stop-Transcript | Out-Null
