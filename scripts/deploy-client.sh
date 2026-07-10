#!/usr/bin/env bash
# deploy-client.sh — provision a Windows 11 client that auto-joins the domain.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/core.sh
source "${HERE}/lib/core.sh"
source "${HERE}/lib/config.sh"
source "${HERE}/lib/proxmox.sh"
source "${HERE}/lib/windows.sh"

deploy_client() {
  require_root; require_pve
  init_lab_secrets

  local storage; storage="$(resolve_disk_storage)"
  # Client sits at base+1 by default so it never collides with the DC.
  local vmid="${SOC_CLIENT_VMID:-$(next_vmid "$((SOC_VMID_BASE + 1))")}"

  msg_info "Resolving Windows 11 + VirtIO ISOs..."
  local win_iso virtio_iso
  win_iso="$(resolve_iso_volume "$SOC_WIN11_ISO_URL" "$SOC_WIN11_ISO_NAME" "Windows 11")" \
    || die "No Windows 11 ISO available."
  virtio_iso="$(resolve_iso_volume "$SOC_VIRTIO_ISO_URL" "$SOC_VIRTIO_ISO_NAME" "VirtIO drivers")" \
    || die "No VirtIO ISO available."

  local work; work="$(mktemp -d)"; trap 'rm -rf "$work"' RETURN
  mkdir -p "${work}/provision"
  local A="${SOC_ASSET_DIR}/autounattend"

  render_template "${A}/client/autounattend.xml" "${work}/autounattend.xml" \
    "HOSTNAME=${SOC_CLIENT_NAME}" "ADMINPASS=$(xml_escape "${SOC_ADMIN_PASSWORD}")" \
    "IMAGE=$(xml_escape "${SOC_WIN11_IMAGE}")"
  render_template "${A}/client/join-domain.ps1" "${work}/provision/join-domain.ps1" \
    "DOMAIN=${SOC_DOMAIN}" "IP=${SOC_CLIENT_IP}" "PREFIX=${SOC_NETMASK}" \
    "GATEWAY=${SOC_GATEWAY}" "DC_IP=${SOC_DC_IP}" "SIEM_IP=${SOC_SIEM_IP}" \
    "ADMINPASS=${SOC_ADMIN_PASSWORD}" "HOSTNAME=${SOC_CLIENT_NAME}"
  render_template "${A}/install-agents.ps1" "${work}/provision/install-agents.ps1" \
    "SIEM_IP=${SOC_SIEM_IP}" "SYSMON_CONFIG_URL=${SOC_SYSMON_CONFIG_URL}" \
    "WAZUH_AGENT_MSI_URL=${SOC_WAZUH_AGENT_MSI_URL}"

  local answer_iso; answer_iso="$(build_answer_iso "$work" "soc-client-answer-${vmid}.iso")"

  build_windows_vm "$vmid" "$SOC_CLIENT_NAME" "win11" \
    "$SOC_CLIENT_CORES" "$SOC_CLIENT_RAM" "$SOC_CLIENT_DISK" \
    "$storage" "$SOC_BRIDGE" "$SOC_VLAN" \
    "$win_iso" "$virtio_iso" "$answer_iso"

  state_set SOC_CLIENT_VMID "$vmid"

  echo
  msg_ok "Windows 11 client VM ${vmid} (${SOC_CLIENT_NAME}) is installing."
  msg_info "Address: ${SOC_CLIENT_IP}/${SOC_NETMASK}  gw ${SOC_GATEWAY}  DNS ${SOC_DC_IP}"
  msg_info "It will join ${SOC_DOMAIN} once the DC is reachable, then install Sysmon + Wazuh."
  msg_warn "Deploy (or finish) the DC first so the domain exists when the client comes up."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  banner "Deploy Windows Client"
  deploy_client
fi
