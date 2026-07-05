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
: "${SOC_DC_CORES:=2}";     : "${SOC_DC_RAM:=4096}";     : "${SOC_DC_DISK:=60}"
: "${SOC_CLIENT_CORES:=2}"; : "${SOC_CLIENT_RAM:=4096}"; : "${SOC_CLIENT_DISK:=64}"
: "${SOC_LINUX_CORES:=2}";  : "${SOC_LINUX_RAM:=2048}";  : "${SOC_LINUX_DISK:=32}"
: "${SOC_SIEM_CORES:=4}";   : "${SOC_SIEM_RAM:=8192}";   : "${SOC_SIEM_DISK:=50}"

# --- Storage ----------------------------------------------------------------
: "${SOC_STORAGE:=}"                     # VM disk storage (blank => prompt/auto)
: "${SOC_ISO_STORAGE:=local}"            # Storage that holds ISOs
: "${SOC_SNIPPET_STORAGE:=local}"        # Storage for cloud-init snippets

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
# Ubuntu cloud image for Linux VMs (analyst box + Wazuh SIEM).
: "${SOC_UBUNTU_IMG_URL:=https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img}"
: "${SOC_UBUNTU_IMG_NAME:=jammy-server-cloudimg-amd64.img}"

# --- Security agents pushed onto Windows endpoints --------------------------
: "${SOC_SYSMON_CONFIG_URL:=https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml}"
: "${SOC_WAZUH_AGENT_MSI_URL:=https://packages.wazuh.com/4.x/windows/wazuh-agent-4.9.0-1.msi}"

# Resolve the repo root and where raw templates live regardless of CWD.
SOC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOC_REPO_ROOT="$(cd "${SOC_LIB_DIR}/../.." && pwd)"
: "${SOC_ASSET_DIR:=${SOC_REPO_ROOT}}"   # Overridden to a temp dir in remote/1-liner mode
