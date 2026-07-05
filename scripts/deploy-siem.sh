#!/usr/bin/env bash
# deploy-siem.sh — provision the Wazuh SIEM all-in-one (manager+indexer+dashboard).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/lib/core.sh"
source "${HERE}/lib/config.sh"
source "${HERE}/lib/proxmox.sh"
source "${HERE}/lib/linux.sh"

deploy_siem() {
  require_root; require_pve
  init_lab_secrets
  ensure_cmd openssl

  local storage; storage="$(resolve_disk_storage)"
  local vmid="${SOC_SIEM_VMID:-$(next_vmid "$((SOC_VMID_BASE + 3))")}"

  local img; img="$(fetch_cloud_image "$SOC_UBUNTU_IMG_URL" "$SOC_UBUNTU_IMG_NAME")" \
    || die "Failed to obtain Ubuntu cloud image."

  local pwhash; pwhash="$(pw_hash "$SOC_USER_PASSWORD")"
  local snippet
  snippet="$(install_snippet "${SOC_ASSET_DIR}/cloudinit/wazuh.yaml" \
      "soc-wazuh-${vmid}.yaml" \
      "HOSTNAME=${SOC_SIEM_NAME}" "LINUX_USER=${SOC_LINUX_USER}" \
      "USER_PWHASH=${pwhash}" "IP=${SOC_SIEM_IP}")"

  # SIEM isn't a domain member: resolve directly via the upstream DNS.
  build_linux_vm "$vmid" "$SOC_SIEM_NAME" \
    "$SOC_SIEM_CORES" "$SOC_SIEM_RAM" "$SOC_SIEM_DISK" \
    "$storage" "$SOC_BRIDGE" "$SOC_VLAN" "$SOC_SIEM_IP" "$SOC_UPSTREAM_DNS" \
    "$img" "$snippet"

  state_set SOC_SIEM_VMID "$vmid"

  echo
  msg_ok "Wazuh SIEM VM ${vmid} (${SOC_SIEM_NAME}) is provisioning."
  msg_info "Dashboard: https://${SOC_SIEM_IP}  (user: admin)"
  msg_info "SSH:       ${SOC_LINUX_USER}@${SOC_SIEM_IP} / (see ${SOC_STATE_DIR}/lab.env)"
  msg_warn "The Wazuh all-in-one install runs on first boot and takes ~10-15 min."
  msg_warn "Dashboard admin password is written on the VM at /root/WAZUH-CREDENTIALS.txt."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  banner "Deploy Wazuh SIEM"
  deploy_siem
fi
