<#
    install-agents.ps1 — install Sysmon (with a good config) and the Wazuh agent
    on a Windows endpoint, pointing the agent at the SIEM manager.

    Params are passed by the caller; @@NAME@@ placeholders provide defaults so the
    script also works if run standalone.
#>
param(
    [string]$SiemIP    = '@@SIEM_IP@@',
    [string]$AgentName = $env:COMPUTERNAME
)
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force 'C:\provision' | Out-Null
Start-Transcript -Path 'C:\provision\install-agents.log' -Append | Out-Null

$SysmonCfgUrl = '@@SYSMON_CONFIG_URL@@'
$WazuhMsiUrl  = '@@WAZUH_AGENT_MSI_URL@@'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Sysmon ------------------------------------------------------------------
try {
    if (-not (Get-Service Sysmon64 -ErrorAction SilentlyContinue)) {
        $zip = 'C:\provision\Sysmon.zip'; $dir = 'C:\provision\Sysmon'
        Invoke-WebRequest 'https://download.sysinternals.com/files/Sysmon.zip' -OutFile $zip -UseBasicParsing
        Expand-Archive $zip $dir -Force
        Invoke-WebRequest $SysmonCfgUrl -OutFile 'C:\provision\sysmonconfig.xml' -UseBasicParsing
        & "$dir\Sysmon64.exe" -accepteula -i 'C:\provision\sysmonconfig.xml'
        Write-Host "Sysmon installed."
    } else { Write-Host "Sysmon already installed." }
} catch { Write-Warning "Sysmon install failed: $_" }

# --- Wazuh agent -------------------------------------------------------------
try {
    if (-not (Get-Service Wazuh -ErrorAction SilentlyContinue) -and
        -not (Get-Service WazuhSvc -ErrorAction SilentlyContinue)) {
        $msi = 'C:\provision\wazuh-agent.msi'
        Invoke-WebRequest $WazuhMsiUrl -OutFile $msi -UseBasicParsing
        Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /q WAZUH_MANAGER=`"$SiemIP`" WAZUH_AGENT_NAME=`"$AgentName`"" -Wait
        Start-Sleep 5
        Start-Service WazuhSvc -ErrorAction SilentlyContinue
        Write-Host "Wazuh agent installed, reporting to $SiemIP as $AgentName."
    } else { Write-Host "Wazuh agent already installed." }
} catch { Write-Warning "Wazuh agent install failed: $_" }

Stop-Transcript | Out-Null
