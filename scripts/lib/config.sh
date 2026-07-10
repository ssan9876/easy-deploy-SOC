#!/usr/bin/env bash
# config.sh — default lab configuration. Every value can be overridden by an
# environment variable of the same name (e.g. SOC_DOMAIN=corp.local) or through
# the interactive menu. Sourced after core.sh.

# --- Identity ---------------------------------------------------------------
: "${SOC_DOMAIN:=soclab.local}"          # AD forest / DNS domain
: "${SOC_NETBIOS:=SOCLAB}"               # NetBIOS name (derive if you change domain)
: "${SOC_ADMIN_PASSWORD:=}"              # Blank => generated & saved to state
: "${SOC_USER_PASSWORD:=}"               # Password for lab AD/Linux users (blank => generated)
: "${SOC_WEAK_SVC_PASSWORD:=Summer2025!}" # Deliberately weak, crackable pw for svc_sql (Kerberoast lab)
: "${SOC_LINUX_USER:=analyst}"           # Default user on Linux VMs

# Where generated secrets + lab facts are persisted between script runs.
: "${SOC_STATE_DIR:=/var/lib/easy-deploy-soc}"

# --- Networking -------------------------------------------------------------
# Network mode:
#   isolated -> create a dedicated, private Proxmox bridge for the lab, with the
#               Proxmox host as its gateway and NAT to the internet. The lab is
#               walled off from your existing LAN. (default)
#   existing -> attach to an existing bridge you already have (set SOC_BRIDGE),
#               using a router/gateway you already run.
: "${SOC_NET_MODE:=isolated}"
: "${SOC_LAB_BRIDGE:=vmbr9}"             # Bridge created/used in isolated mode
: "${SOC_NET_NAT:=1}"                    # 1 = NAT the lab subnet out to the internet
: "${SOC_UPSTREAM_DNS:=1.1.1.1}"         # Resolver for internet lookups (via NAT)

: "${SOC_VLAN:=}"                        # Optional VLAN tag (blank = none)
: "${SOC_SUBNET:=10.0.0}"                # /24 lab subnet (no trailing octet)
: "${SOC_GATEWAY:=10.0.0.1}"             # Lab gateway (the Proxmox host in isolated mode)
: "${SOC_NETMASK:=24}"                   # CIDR prefix length

# Publish the Wazuh dashboard off the isolated lab network so you can reach it
# from a machine that is NOT on the Proxmox lab subnet. In isolated mode this
# adds a port-forward (DNAT) on the Proxmox host: browse to
# https://<proxmox-host-ip>:<SOC_SIEM_PUBLISH_PORT> and it lands on the SIEM's
# :443. Set SOC_PUBLISH_SIEM=0 to keep the SIEM fully walled off.
: "${SOC_PUBLISH_SIEM:=1}"               # 1 = port-forward the SIEM dashboard to the host
: "${SOC_SIEM_PUBLISH_PORT:=8443}"       # Host port that forwards to the SIEM's :443

# Publish RDP for the desktop VMs off the isolated lab, the same way as the SIEM
# dashboard: from a machine that is NOT on the lab subnet, point Remote Desktop
# at <proxmox-host-ip>:<port> and it lands on that VM's :3389. Set
# SOC_PUBLISH_RDP=0 to keep the desktops reachable only from inside the lab.
: "${SOC_PUBLISH_RDP:=1}"                 # 1 = port-forward RDP for the desktop VMs to the host
: "${SOC_RDP_DC_PORT:=13389}"            # Host port -> Domain Controller (SOC_DC_IP:3389)
: "${SOC_RDP_CLIENT_PORT:=23389}"        # Host port -> Windows client   (SOC_CLIENT_IP:3389)
: "${SOC_RDP_LINUX_PORT:=33389}"         # Host port -> Kali analyst box  (SOC_LINUX_IP:3389)

# The bridge VMs attach to. In isolated mode this defaults to the lab bridge;
# in existing mode it defaults to vmbr0. An explicit SOC_BRIDGE always wins.
if [[ "$SOC_NET_MODE" == "isolated" ]]; then
  : "${SOC_BRIDGE:=$SOC_LAB_BRIDGE}"
else
  : "${SOC_BRIDGE:=vmbr0}"
fi

# Static IPs for lab members (last octet appended to SOC_SUBNET)
: "${SOC_DC_IP:=10.0.0.10}"              # Domain Controller (also DNS)
: "${SOC_CLIENT_IP:=10.0.0.20}"          # Windows client
: "${SOC_LINUX_IP:=10.0.0.30}"           # Linux analyst box
: "${SOC_SIEM_IP:=10.0.0.40}"            # Wazuh SIEM manager

# --- VM identity ------------------------------------------------------------
: "${SOC_VMID_BASE:=900}"                # First VMID; members use base+0..3
: "${SOC_DC_NAME:=soc-dc01}"
: "${SOC_CLIENT_NAME:=soc-win11}"
: "${SOC_LINUX_NAME:=soc-linux01}"
: "${SOC_SIEM_NAME:=soc-wazuh01}"

# --- Resources (cores / MB RAM / GB disk) -----------------------------------
# The Linux analyst box runs a full Kali desktop (XFCE) + toolset by default, so
# it is sized more generously than a headless box would be.
: "${SOC_DC_CORES:=2}";     : "${SOC_DC_RAM:=4096}";     : "${SOC_DC_DISK:=60}"
: "${SOC_CLIENT_CORES:=2}"; : "${SOC_CLIENT_RAM:=4096}"; : "${SOC_CLIENT_DISK:=64}"
: "${SOC_LINUX_CORES:=2}";  : "${SOC_LINUX_RAM:=4096}";  : "${SOC_LINUX_DISK:=60}"
: "${SOC_SIEM_CORES:=4}";   : "${SOC_SIEM_RAM:=8192}";   : "${SOC_SIEM_DISK:=50}"

# --- Storage ----------------------------------------------------------------
: "${SOC_STORAGE:=}"                     # VM disk storage (blank => prompt/auto)
: "${SOC_ISO_STORAGE:=local}"            # Storage that holds ISOs
: "${SOC_SNIPPET_STORAGE:=local}"        # Storage for cloud-init snippets

# --- Windows image selection ------------------------------------------------
# Which edition inside the Windows Server ISO to install. The default is the
# **Desktop Experience** (full GUI) edition so the DC is not a Server-Core CLI.
# If your ISO uses a different label the install will halt — list the names in
# your ISO with `dism /Get-WimInfo /WimFile:<mount>\sources\install.wim` and set
# SOC_WINSRV_IMAGE to match (e.g. "...Datacenter Evaluation (Desktop Experience)").
: "${SOC_WINSRV_IMAGE:=Windows Server 2022 Standard Evaluation (Desktop Experience)}"
: "${SOC_WIN11_IMAGE:=Windows 11 Enterprise Evaluation}"

# --- ISO sources (override if links rot or to use your own uploads) ---------
# Windows Server 2022 Evaluation (180-day). From Microsoft Evaluation Center.
: "${SOC_WINSRV_ISO_URL:=https://software-static.download.prss.microsoft.com/sg/download/888969d5-f34g-4e03-ac9d-1f9786c66749/SERVER_EVAL_x64FRE_en-us.iso}"
: "${SOC_WINSRV_ISO_NAME:=SERVER_2022_EVAL_x64.iso}"
# Windows 11 Enterprise Evaluation (90-day). From Microsoft Evaluation Center.
: "${SOC_WIN11_ISO_URL:=https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/22631.2428.231001-0608.23H2_NI_RELEASE_SVC_REFRESH_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso}"
: "${SOC_WIN11_ISO_NAME:=WIN11_23H2_ENT_EVAL_x64.iso}"
# VirtIO Windows drivers (stable, from Fedora).
: "${SOC_VIRTIO_ISO_URL:=https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso}"
: "${SOC_VIRTIO_ISO_NAME:=virtio-win.iso}"
# Ubuntu cloud image for the Wazuh SIEM (kept lean/headless).
: "${SOC_UBUNTU_IMG_URL:=https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img}"
: "${SOC_UBUNTU_IMG_NAME:=jammy-server-cloudimg-amd64.img}"

# --- Kali analyst box -------------------------------------------------------
# The analyst/attacker box runs Kali Linux with an XFCE desktop by default.
# Kali ships cloud-init "generic cloud" images as .tar.xz archives (containing a
# raw disk); the deployer discovers the newest one under SOC_KALI_BASE_URL and
# extracts it automatically. Pin SOC_KALI_IMG_URL/NAME to a specific file if the
# auto-discovery can't reach kali.download.
: "${SOC_LINUX_DESKTOP:=1}"              # 1 = install the Kali XFCE desktop (0 = headless Kali)
: "${SOC_KALI_BASE_URL:=https://kali.download/cloud-images/current/}"
: "${SOC_KALI_IMG_URL:=}"                # blank => auto-discover under SOC_KALI_BASE_URL
: "${SOC_KALI_IMG_NAME:=}"               # blank => derived from the discovered URL

# --- Security agents pushed onto Windows endpoints --------------------------
: "${SOC_SYSMON_CONFIG_URL:=https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml}"
: "${SOC_WAZUH_AGENT_MSI_URL:=https://packages.wazuh.com/4.x/windows/wazuh-agent-4.9.0-1.msi}"

# Resolve the repo root and where raw templates live regardless of CWD.
SOC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOC_REPO_ROOT="$(cd "${SOC_LIB_DIR}/../.." && pwd)"
: "${SOC_ASSET_DIR:=${SOC_REPO_ROOT}}"   # Overridden to a temp dir in remote/1-liner mode
