#!/usr/bin/env bash
# deploy-dc.sh — provision the Windows Server 2022 Domain Controller.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/core.sh
source "${HERE}/lib/core.sh"
# shellcheck source=lib/config.sh
source "${HERE}/lib/config.sh"
# shellcheck source=lib/proxmox.sh
source "${HERE}/lib/proxmox.sh"
# shellcheck source=lib/windows.sh
source "${HERE}/lib/windows.sh"

deploy_dc() {
  require_root; require_pve
  init_lab_secrets

  local storage; storage="$(resolve_disk_storage)"
  local vmid="${SOC_DC_VMID:-$(next_vmid "$SOC_VMID_BASE")}"

  msg_info "Resolving Windows Server + VirtIO ISOs..."
  local win_iso virtio_iso
  win_iso="$(resolve_iso_volume "$SOC_WINSRV_ISO_URL" "$SOC_WINSRV_ISO_NAME" "Windows Server 2022")" \
    || die "No Windows Server ISO available."
  virtio_iso="$(resolve_iso_volume "$SOC_VIRTIO_ISO_URL" "$SOC_VIRTIO_ISO_NAME" "VirtIO drivers")" \
    || die "No VirtIO ISO available."

  # --- Build the answer ISO (autounattend.xml at root, scripts under provision/) ---
  local work; work="$(mktemp -d)"; trap 'rm -rf "$work"' RETURN
  mkdir -p "${work}/provision"
  local A="${SOC_ASSET_DIR}/autounattend"

  render_template "${A}/dc/autounattend.xml" "${work}/autounattend.xml" \
    "HOSTNAME=${SOC_DC_NAME}" "ADMINPASS=$(xml_escape "${SOC_ADMIN_PASSWORD}")" \
    "IMAGE=$(xml_escape "${SOC_WINSRV_IMAGE}")"
  render_template "${A}/dc/setup-dc.ps1" "${work}/provision/setup-dc.ps1" \
    "DOMAIN=${SOC_DOMAIN}" "NETBIOS=${SOC_NETBIOS}" "IP=${SOC_DC_IP}" \
    "PREFIX=${SOC_NETMASK}" "GATEWAY=${SOC_GATEWAY}" "UPSTREAM_DNS=${SOC_UPSTREAM_DNS}" \
    "ADMINPASS=${SOC_ADMIN_PASSWORD}"
  render_template "${A}/dc/dc-stage2.ps1" "${work}/provision/dc-stage2.ps1" \
    "DOMAIN=${SOC_DOMAIN}" "SIEM_IP=${SOC_SIEM_IP}" "USERPASS=${SOC_USER_PASSWORD}" \
    "WEAK_SVC_PASSWORD=${SOC_WEAK_SVC_PASSWORD}" "UPSTREAM_DNS=${SOC_UPSTREAM_DNS}"
  render_template "${A}/install-agents.ps1" "${work}/provision/install-agents.ps1" \
    "SIEM_IP=${SOC_SIEM_IP}" "SYSMON_CONFIG_URL=${SOC_SYSMON_CONFIG_URL}" \
    "WAZUH_AGENT_MSI_URL=${SOC_WAZUH_AGENT_MSI_URL}"

  local answer_iso; answer_iso="$(build_answer_iso "$work" "soc-dc-answer-${vmid}.iso")"

  build_windows_vm "$vmid" "$SOC_DC_NAME" "win11" \
    "$SOC_DC_CORES" "$SOC_DC_RAM" "$SOC_DC_DISK" \
    "$storage" "$SOC_BRIDGE" "$SOC_VLAN" \
    "$win_iso" "$virtio_iso" "$answer_iso"

  # Record facts for later components.
  state_set SOC_DC_VMID "$vmid"

  echo
  msg_ok "Domain Controller VM ${vmid} (${SOC_DC_NAME}) is installing."
  msg_info "Forest:  ${SOC_DOMAIN}  (NetBIOS ${SOC_NETBIOS})"
  msg_info "Address: ${SOC_DC_IP}/${SOC_NETMASK}  gw ${SOC_GATEWAY}  (DNS = itself)"
  msg_info "Login:   Administrator / (see ${SOC_STATE_DIR}/lab.env)"
  msg_warn "Unattended install + DC promotion take ~15-25 min and reboot twice."
}

# Allow running standalone.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  banner "Deploy Domain Controller"
  deploy_dc
fi
