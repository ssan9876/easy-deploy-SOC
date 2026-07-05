#!/usr/bin/env bash
# setup-network.sh — create the isolated lab network on the Proxmox host.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/lib/core.sh"
source "${HERE}/lib/config.sh"
source "${HERE}/lib/proxmox.sh"
source "${HERE}/lib/network.sh"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  banner "Set up isolated lab network"
  if [[ "$SOC_NET_MODE" != "isolated" ]]; then
    msg_warn "SOC_NET_MODE is '${SOC_NET_MODE}', not 'isolated'."
    msg_warn "VMs will attach to existing bridge '${SOC_BRIDGE}'. Nothing to create."
    exit 0
  fi
  create_lab_network
  msg_info "Bridge:  ${SOC_BRIDGE}"
  msg_info "Gateway: ${SOC_GATEWAY}/${SOC_NETMASK} (this Proxmox host)"
  msg_info "Subnet:  ${SOC_SUBNET}.0/${SOC_NETMASK}"
fi
