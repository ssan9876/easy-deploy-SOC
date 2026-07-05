<#
    setup-dc.ps1 — runs at first logon on the Domain Controller.
    Configures static networking, installs the AD DS + DNS roles, and promotes
    this machine to the first DC of a new forest. Reboots automatically.

    Placeholders (@@NAME@@) are substituted by scripts/deploy-dc.sh at build time.
    Idempotent-ish: skips promotion if the domain already exists.
#>

$ErrorActionPreference = 'Stop'
$log = 'C:\provision\setup-dc.log'
New-Item -ItemType Directory -Force 'C:\provision' | Out-Null
Start-Transcript -Path $log -Append | Out-Null

$Domain    = '@@DOMAIN@@'
$NetBIOS   = '@@NETBIOS@@'
$IP        = '@@IP@@'
$Prefix    = @@PREFIX@@
$Gateway   = '@@GATEWAY@@'
$Upstream  = '@@UPSTREAM_DNS@@'
$SafePass  = '@@ADMINPASS@@'

Write-Host "== easy-deploy-SOC DC provisioning for $Domain =="

# --- 1. Install VirtIO guest tools / qemu-guest-agent if the ISO is attached ---
try {
    $vg = Get-ChildItem -Path (Get-PSDrive -PSProvider FileSystem | ForEach-Object Root) `
            -Filter 'virtio-win-guest-tools.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($vg) {
        Write-Host "Installing VirtIO guest tools from $($vg.FullName)"
        Start-Process -FilePath $vg.FullName -ArgumentList '/install','/quiet','/norestart' -Wait
    }
} catch { Write-Warning "VirtIO tools install skipped: $_" }

# --- 2. Static networking (DC points DNS at itself) --------------------------
$if = Get-NetAdapter -Physical | Where-Object Status -eq 'Up' | Select-Object -First 1
if (-not $if) { $if = Get-NetAdapter -Physical | Select-Object -First 1 }
Write-Host "Configuring $($if.Name): $IP/$Prefix gw $Gateway"

Get-NetIPAddress -InterfaceIndex $if.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -ne $IP } |
    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
Remove-NetRoute -InterfaceIndex $if.ifIndex -Confirm:$false -ErrorAction SilentlyContinue

New-NetIPAddress -InterfaceIndex $if.ifIndex -IPAddress $IP -PrefixLength $Prefix `
    -DefaultGateway $Gateway -ErrorAction SilentlyContinue | Out-Null
# Before promotion, resolve via an upstream resolver; Install-ADDSForest then
# repoints the DC's own DNS client to itself (127.0.0.1).
Set-DnsClientServerAddress -InterfaceIndex $if.ifIndex -ServerAddresses '127.0.0.1',$Upstream

# --- 3. Install AD DS + DNS and promote to a new forest ----------------------
if (Get-Service NTDS -ErrorAction SilentlyContinue) {
    Write-Host "AD DS already present; skipping promotion."
} else {
    Write-Host "Installing AD-Domain-Services + DNS roles..."
    Install-WindowsFeature -Name AD-Domain-Services,DNS -IncludeManagementTools | Out-Null

    # Register stage 2 (lab users + endpoint agents) to run after the reboot.
    if (Test-Path 'C:\provision\dc-stage2.ps1') {
        Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' `
            -Name 'SocDcStage2' `
            -Value 'powershell.exe -ExecutionPolicy Bypass -NoProfile -File C:\provision\dc-stage2.ps1'
    }

    Write-Host "Promoting to first DC of forest $Domain ..."
    Import-Module ADDSDeployment
    $safe = ConvertTo-SecureString $SafePass -AsPlainText -Force
    Install-ADDSForest `
        -DomainName $Domain `
        -DomainNetbiosName $NetBIOS `
        -SafeModeAdministratorPassword $safe `
        -InstallDns `
        -DomainMode 'WinThreshold' `
        -ForestMode 'WinThreshold' `
        -NoRebootOnCompletion:$false `
        -Force
    # Install-ADDSForest triggers the reboot; nothing after this runs.
}

Stop-Transcript | Out-Null
