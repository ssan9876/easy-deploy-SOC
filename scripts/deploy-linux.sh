#!/usr/bin/env bash
# deploy-linux.sh — provision the Ubuntu analyst / attacker workstation.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/lib/core.sh"
source "${HERE}/lib/config.sh"
source "${HERE}/lib/proxmox.sh"
source "${HERE}/lib/linux.sh"

deploy_linux() {
  require_root; require_pve
  init_lab_secrets
  ensure_cmd openssl

  local storage; storage="$(resolve_disk_storage)"
  local vmid="${SOC_LINUX_VMID:-$(next_vmid "$((SOC_VMID_BASE + 2))")}"

  local img; img="$(fetch_cloud_image "$SOC_UBUNTU_IMG_URL" "$SOC_UBUNTU_IMG_NAME")" \
    || die "Failed to obtain Ubuntu cloud image."

  local pwhash; pwhash="$(pw_hash "$SOC_USER_PASSWORD")"
  local snippet
  snippet="$(install_snippet "${SOC_ASSET_DIR}/cloudinit/linux-analyst.yaml" \
      "soc-linux-${vmid}.yaml" \
      "HOSTNAME=${SOC_LINUX_NAME}" "LINUX_USER=${SOC_LINUX_USER}" \
      "USER_PWHASH=${pwhash}" "SIEM_IP=${SOC_SIEM_IP}")"

  # Analyst box uses the DC for DNS so it can resolve/enumerate the domain.
  build_linux_vm "$vmid" "$SOC_LINUX_NAME" \
    "$SOC_LINUX_CORES" "$SOC_LINUX_RAM" "$SOC_LINUX_DISK" \
    "$storage" "$SOC_BRIDGE" "$SOC_VLAN" "$SOC_LINUX_IP" "$SOC_DC_IP" \
    "$img" "$snippet"

  state_set SOC_LINUX_VMID "$vmid"

  echo
  msg_ok "Analyst box VM ${vmid} (${SOC_LINUX_NAME}) is provisioning."
  msg_info "Address: ${SOC_LINUX_IP}/${SOC_NETMASK}  gw ${SOC_GATEWAY}  DNS ${SOC_DC_IP}"
  msg_info "Login:   ${SOC_LINUX_USER} / (see ${SOC_STATE_DIR}/lab.env)"
  msg_info "Ships a Wazuh agent to ${SOC_SIEM_IP}; ships nmap/ldapsearch/smbclient/krb5."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  banner "Deploy Linux Analyst Box"
  deploy_linux
fi
