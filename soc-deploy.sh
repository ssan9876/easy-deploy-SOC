#!/usr/bin/env bash
# soc-deploy.sh — one-line SOC homelab deployer for Proxmox VE.
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/ssan9876/easy-deploy-SOC/main/soc-deploy.sh)"
#
# Provisions a self-contained Security Operations Center practice lab:
#   • Windows Server 2022  -> Domain Controller + DNS (soclab.local)
#   • Windows 11 client    -> auto-joined, Sysmon + Wazuh agent
#   • Ubuntu analyst box   -> red/blue tooling + Wazuh agent
#   • Wazuh SIEM           -> collects logs from every endpoint
set -euo pipefail

REPO_SLUG="${SOC_REPO_SLUG:-ssan9876/easy-deploy-SOC}"
REPO_BRANCH="${SOC_REPO_BRANCH:-main}"

# --- Locate assets, bootstrapping from GitHub when run via curl --------------
locate_or_bootstrap() {
  local self_dir=""
  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]:-}" ]]; then
    self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  fi
  if [[ -n "$self_dir" && -f "${self_dir}/scripts/lib/core.sh" ]]; then
    SOC_ASSET_DIR="$self_dir"
    return
  fi
  # Piped from curl: fetch a tarball of the repo into a temp dir.
  echo "Bootstrapping easy-deploy-SOC assets from ${REPO_SLUG}@${REPO_BRANCH}..." >&2
  command -v curl >/dev/null 2>&1 || { echo "curl is required." >&2; exit 1; }
  command -v tar  >/dev/null 2>&1 || { echo "tar is required." >&2; exit 1; }
  local tmp; tmp="$(mktemp -d)"
  if ! curl -fsSL "https://codeload.github.com/${REPO_SLUG}/tar.gz/refs/heads/${REPO_BRANCH}" \
        | tar xz -C "$tmp" --strip-components=1; then
    echo "Failed to download repository assets." >&2
    exit 1
  fi
  SOC_ASSET_DIR="$tmp"
}

locate_or_bootstrap
export SOC_ASSET_DIR
LIB="${SOC_ASSET_DIR}/scripts/lib"
DEPLOY="${SOC_ASSET_DIR}/scripts"

# shellcheck source=scripts/lib/core.sh
source "${LIB}/core.sh"
source "${LIB}/config.sh"
source "${LIB}/proxmox.sh"
source "${LIB}/network.sh"
source "${LIB}/windows.sh"
source "${LIB}/linux.sh"
# Source deploy scripts for their functions (guarded, so they don't self-run).
source "${DEPLOY}/deploy-dc.sh"
source "${DEPLOY}/deploy-client.sh"
source "${DEPLOY}/deploy-linux.sh"
source "${DEPLOY}/deploy-siem.sh"
source "${DEPLOY}/destroy-lab.sh"

# Prompt for a password (twice, must match; blank keeps the current/auto value).
# A single-quote breaks the PowerShell literals used in Windows setup, so reject it.
# Echoes the chosen password, or nothing to signal "leave as-is".
prompt_password() { # label
  local label="$1" p1 p2
  while true; do
    p1="$(wt_password 'Passwords' "${label} (blank = keep current / auto-generate):")" || return 1
    [[ -z "$p1" ]] && return 0            # blank => caller keeps existing value
    if [[ "$p1" == *"'"* ]]; then
      msg_warn "Password can't contain a single quote ' — it breaks Windows setup. Try again."
      continue
    fi
    p2="$(wt_password 'Passwords' "Confirm ${label}:")" || return 1
    if [[ "$p1" != "$p2" ]]; then
      msg_warn "Passwords didn't match. Try again."
      continue
    fi
    printf '%s' "$p1"; return 0
  done
}

# --- Interactive configuration ----------------------------------------------
configure() {
  SOC_DOMAIN="$(wt_input 'Domain' 'AD forest / DNS domain:' "$SOC_DOMAIN")" || return
  SOC_NETBIOS="$(echo "${SOC_DOMAIN%%.*}" | tr '[:lower:]' '[:upper:]')"
  SOC_SUBNET="$(wt_input 'Network' 'Lab /24 subnet (first three octets):' "$SOC_SUBNET")" || return
  SOC_GATEWAY="$(wt_input 'Network' 'Lab gateway:' "${SOC_SUBNET}.1")" || return
  SOC_DC_IP="$(wt_input 'Network' 'Domain Controller IP:' "${SOC_SUBNET}.10")" || return
  SOC_CLIENT_IP="$(wt_input 'Network' 'Windows client IP:' "${SOC_SUBNET}.20")" || return
  SOC_LINUX_IP="$(wt_input 'Network' 'Linux analyst IP:' "${SOC_SUBNET}.30")" || return
  SOC_SIEM_IP="$(wt_input 'Network' 'Wazuh SIEM IP:' "${SOC_SUBNET}.40")" || return
  SOC_BRIDGE="$(wt_input 'Network' 'Proxmox bridge:' "$SOC_BRIDGE")" || return
  SOC_VLAN="$(wt_input 'Network' 'VLAN tag (blank for none):' "$SOC_VLAN")" || return
  SOC_VMID_BASE="$(wt_input 'VMIDs' 'Base VMID (uses base..base+3):' "$SOC_VMID_BASE")" || return
  SOC_STORAGE="$(wt_input 'Storage' 'VM disk storage (blank = auto/prompt):' "$SOC_STORAGE")" || return
  SOC_NET_MODE="$(wt_menu 'Network' 'Lab network mode:' \
      isolated 'Dedicated private bridge + NAT (recommended)' \
      existing 'Attach to an existing bridge/router')" || return
  if [[ "$SOC_NET_MODE" == "isolated" ]]; then
    SOC_LAB_BRIDGE="$(wt_input 'Network' 'Name for the isolated lab bridge:' "$SOC_LAB_BRIDGE")" || return
    SOC_BRIDGE="$SOC_LAB_BRIDGE"
    SOC_GATEWAY="${SOC_SUBNET}.1"   # Proxmox host is the gateway in isolated mode
  else
    SOC_BRIDGE="$(wt_input 'Network' 'Existing Proxmox bridge:' "$SOC_BRIDGE")" || return
    SOC_GATEWAY="$(wt_input 'Network' 'Existing lab gateway/router:' "$SOC_GATEWAY")" || return
  fi

  # Reach the Wazuh dashboard from a PC that isn't on the lab subnet.
  if [[ "$SOC_NET_MODE" == "isolated" ]]; then
    if wt_yesno 'Wazuh access' "Publish the Wazuh dashboard on the Proxmox host so you can open it from your own PC (not on the lab network)?"; then
      SOC_PUBLISH_SIEM=1
      SOC_SIEM_PUBLISH_PORT="$(wt_input 'Wazuh access' 'Host port to forward to the SIEM dashboard (:443):' "$SOC_SIEM_PUBLISH_PORT")" || return
    else
      SOC_PUBLISH_SIEM=0
    fi
  fi

  # Let the operator pick their own passwords instead of the generated ones.
  local pw
  if pw="$(prompt_password 'Windows Administrator / lab admin password')"; then
    [[ -n "$pw" ]] && SOC_ADMIN_PASSWORD="$pw"
  fi
  if pw="$(prompt_password 'Lab user (AD user / Kali analyst) password')"; then
    [[ -n "$pw" ]] && SOC_USER_PASSWORD="$pw"
  fi

  export SOC_DOMAIN SOC_NETBIOS SOC_SUBNET SOC_GATEWAY SOC_DC_IP SOC_CLIENT_IP \
         SOC_LINUX_IP SOC_SIEM_IP SOC_BRIDGE SOC_VLAN SOC_VMID_BASE SOC_STORAGE \
         SOC_NET_MODE SOC_LAB_BRIDGE SOC_NET_NAT SOC_UPSTREAM_DNS \
         SOC_PUBLISH_SIEM SOC_SIEM_PUBLISH_PORT SOC_ADMIN_PASSWORD SOC_USER_PASSWORD
  msg_ok "Configuration updated."
}

summary() {
  local netdesc
  if [[ "$SOC_NET_MODE" == "isolated" ]]; then
    netdesc="isolated bridge ${SOC_BRIDGE} (NAT=${SOC_NET_NAT}), host is gateway ${SOC_GATEWAY}"
  else
    netdesc="existing bridge ${SOC_BRIDGE}, gateway ${SOC_GATEWAY}"
  fi
  cat <<EOF

  Domain / forest : ${SOC_DOMAIN}  (NetBIOS ${SOC_NETBIOS})
  Network         : ${netdesc}${SOC_VLAN:+ (VLAN ${SOC_VLAN})}
  Subnet          : ${SOC_SUBNET}.0/${SOC_NETMASK}   upstream DNS ${SOC_UPSTREAM_DNS}
  DC   ${SOC_DC_NAME}    -> ${SOC_DC_IP}
  Win  ${SOC_CLIENT_NAME} -> ${SOC_CLIENT_IP}
  Lnx  ${SOC_LINUX_NAME}  -> ${SOC_LINUX_IP}
  SIEM ${SOC_SIEM_NAME}  -> ${SOC_SIEM_IP}
  VMIDs           : ${SOC_VMID_BASE}..$((SOC_VMID_BASE + 3))
EOF
}

deploy_full() {
  summary
  if ! wt_yesno "Deploy full SOC lab" "This creates 4 VMs (2 Windows, 2 Linux) with the settings above. Proceed?"; then
    msg_warn "Cancelled."; return
  fi
  init_lab_secrets
  # In isolated mode, stand up the private bridge + NAT before any VM boots.
  [[ "$SOC_NET_MODE" == "isolated" ]] && create_lab_network
  # SIEM first (long install), then DC, then Linux, then client (waits for DC).
  deploy_siem
  deploy_dc
  deploy_linux
  deploy_client
  show_info
}

show_info() {
  local f="${SOC_STATE_DIR}/lab.env"
  echo
  msg_ok "Lab state / credentials: ${f}"
  [[ -f "$f" ]] && { echo; sed 's/^/    /' "$f"; echo; }
  cat <<EOF
  Next steps:
    • Windows installs run unattended (~15-25 min, two reboots each).
    • Wazuh dashboard (on the lab net): https://${SOC_SIEM_IP}  (admin password on
      the SIEM VM at /root/WAZUH-CREDENTIALS.txt once its install finishes).
EOF
  if [[ "$SOC_NET_MODE" == "isolated" && "$SOC_PUBLISH_SIEM" == "1" ]]; then
    local hip; hip="$(host_lan_ip)"
    echo "    • Wazuh dashboard (from your own PC): https://${hip:-<proxmox-host-ip>}:${SOC_SIEM_PUBLISH_PORT}"
  fi
  cat <<EOF
    • Endpoints appear in Wazuh > Agents as they finish provisioning.
    • RDP to ${SOC_DC_IP} (Server desktop) / ${SOC_CLIENT_IP}; SSH to ${SOC_LINUX_IP} / ${SOC_SIEM_IP}.
    • ${SOC_LINUX_NAME} is Kali w/ XFCE desktop — open its Proxmox console or RDP to ${SOC_LINUX_IP}.
EOF
}

# In isolated mode, make sure the private bridge is up before deploying a VM.
ensure_lab_network() {
  [[ "$SOC_NET_MODE" == "isolated" ]] || return 0
  ip link show "$SOC_BRIDGE" >/dev/null 2>&1 && return 0
  create_lab_network
}

main_menu() {
  while true; do
    local choice
    choice="$(wt_menu 'easy-deploy-SOC' 'Choose an action:' \
      full     'Deploy the FULL SOC lab (all 4 VMs)' \
      network  'Set up the isolated lab network only' \
      publish  'Publish the Wazuh dashboard to your PC (host port-forward)' \
      dc       'Deploy Domain Controller only' \
      client   'Deploy Windows 11 client only' \
      linux    'Deploy Linux analyst box only' \
      siem     'Deploy Wazuh SIEM only' \
      config   'Configure lab settings (network, domain, storage)' \
      info     'Show lab info / credentials' \
      destroy  'Destroy the lab (delete all created VMs)' \
      quit     'Quit')" || break
    case "$choice" in
      full)    deploy_full ;;
      network) if [[ "$SOC_NET_MODE" == "isolated" ]]; then create_lab_network; else
                 msg_warn "SOC_NET_MODE=existing; no bridge to create (using ${SOC_BRIDGE})."; fi ;;
      publish) if [[ "$SOC_NET_MODE" == "isolated" ]]; then
                 SOC_PUBLISH_SIEM=1; export SOC_PUBLISH_SIEM
                 SOC_SIEM_PUBLISH_PORT="$(wt_input 'Wazuh access' 'Host port to forward to the SIEM dashboard (:443):' "$SOC_SIEM_PUBLISH_PORT")" || continue
                 export SOC_SIEM_PUBLISH_PORT; create_lab_network
               else
                 msg_warn "SOC_NET_MODE=existing; forward host:${SOC_SIEM_PUBLISH_PORT} -> ${SOC_SIEM_IP}:443 on your own router instead."; fi ;;
      dc)      init_lab_secrets; ensure_lab_network; deploy_dc; show_info ;;
      client)  init_lab_secrets; ensure_lab_network; deploy_client; show_info ;;
      linux)   init_lab_secrets; ensure_lab_network; deploy_linux; show_info ;;
      siem)    init_lab_secrets; ensure_lab_network; deploy_siem; show_info ;;
      config)  configure ;;
      info)    show_info; wt_yesno 'Info' 'Return to menu?' || break ;;
      destroy) destroy_lab ;;
      quit|*)  break ;;
    esac
  done
}

main() {
  banner
  require_root
  require_pve
  ensure_cmd whiptail whiptail || true
  HAS_WHIPTAIL=0; command -v whiptail >/dev/null 2>&1 && HAS_WHIPTAIL=1
  main_menu
  msg_ok "Done. Re-run this script anytime to add or rebuild lab members."
}

main "$@"
