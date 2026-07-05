#!/usr/bin/env bash
# destroy-lab.sh — tear down every VM this toolkit created, plus generated
# answer ISOs / cloud-init snippets. Reads VMIDs from the state file.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/lib/core.sh"
source "${HERE}/lib/config.sh"
source "${HERE}/lib/proxmox.sh"
source "${HERE}/lib/network.sh"

destroy_lab() {
  require_root; require_pve
  banner "Destroy SOC lab"

  local f="${SOC_STATE_DIR}/lab.env"
  # shellcheck source=/dev/null
  [[ -f "$f" ]] && source "$f"

  local -a vmids=()
  for v in "${SOC_DC_VMID:-}" "${SOC_CLIENT_VMID:-}" "${SOC_LINUX_VMID:-}" "${SOC_SIEM_VMID:-}"; do
    [[ -n "$v" ]] && vmids+=("$v")
  done

  if [[ ${#vmids[@]} -eq 0 ]]; then
    msg_warn "No recorded VMIDs in ${f}. Nothing to remove."
    msg_info "You can still remove VMs manually with: qm stop <id> && qm destroy <id>"
    return
  fi

  msg_warn "About to permanently destroy VMs: ${vmids[*]}"
  if ! wt_yesno "Destroy SOC lab" "PERMANENTLY delete these VMs and their disks?\n\n${vmids[*]}\n\nThis cannot be undone."; then
    msg_warn "Cancelled."; return
  fi

  for v in "${vmids[@]}"; do
    if vm_exists "$v"; then
      msg_info "Stopping and destroying VM ${v}"
      qm stop "$v" >/dev/null 2>&1 || true
      sleep 2
      qm destroy "$v" --destroy-unreferenced-disks 1 --purge 1 >/dev/null 2>&1 \
        && msg_ok "Destroyed VM ${v}" || msg_warn "Could not destroy VM ${v} (already gone?)"
    else
      msg_warn "VM ${v} not found; skipping."
    fi
  done

  # Clean generated answer ISOs and snippets.
  local isodir; isodir="$(iso_storage_path "$SOC_ISO_STORAGE")"
  rm -f "${isodir}"/soc-dc-answer-*.iso "${isodir}"/soc-client-answer-*.iso 2>/dev/null || true
  local sndir; sndir="$(snippet_storage_path "$(resolve_snippet_storage)")"
  rm -f "${sndir}"/soc-linux-*.yaml "${sndir}"/soc-wazuh-*.yaml 2>/dev/null || true
  msg_ok "Removed generated answer ISOs and cloud-init snippets."

  # Offer to remove the isolated lab bridge, if we created one.
  if grep -q "easy-deploy-SOC" "$SOC_IF_FILE" 2>/dev/null; then
    if wt_yesno "Network" "Also remove the isolated lab bridge and its NAT rules?"; then
      destroy_lab_network
    fi
  fi

  if wt_yesno "State" "Also remove the state file (${f}) with saved credentials?"; then
    rm -f "$f"; msg_ok "Removed ${f}"
  fi
  msg_ok "SOC lab teardown complete."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  destroy_lab
fi
