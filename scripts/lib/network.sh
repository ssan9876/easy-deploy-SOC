#!/usr/bin/env bash
# network.sh — create/destroy a dedicated, isolated Proxmox bridge for the lab.
# The Proxmox host becomes the lab's gateway (SOC_GATEWAY on SOC_BRIDGE) and,
# when SOC_NET_NAT=1, masquerades the lab subnet out the host's WAN interface so
# the lab can reach the internet while staying walled off from your LAN.
# Requires core.sh, config.sh, proxmox.sh already sourced.

SOC_IF_FILE="/etc/network/interfaces"
SOC_NET_BEGIN="# BEGIN easy-deploy-SOC lab network"
SOC_NET_END="# END easy-deploy-SOC lab network"

# The host's default-route (WAN) interface, used as the NAT egress.
wan_interface() { ip -4 route show default 2>/dev/null | awk '{print $5; exit}'; }

# Remove our managed block from /etc/network/interfaces (idempotent).
_strip_net_block() {
  [[ -f "$SOC_IF_FILE" ]] || return 0
  sed -i "/^${SOC_NET_BEGIN}\$/,/^${SOC_NET_END}\$/d" "$SOC_IF_FILE"
  # Drop a trailing blank line we may have left behind.
  sed -i -e :a -e '/^\n*$/{$d;N;ba}' "$SOC_IF_FILE" 2>/dev/null || true
}

# Apply interface changes with ifupdown2 (Proxmox) or fall back to ifup.
_apply_net() {
  if command -v ifreload >/dev/null 2>&1; then
    ifreload -a || die "ifreload failed. Check ${SOC_IF_FILE}."
  else
    ifup "$SOC_BRIDGE" 2>/dev/null || true
  fi
}

# Create the isolated lab bridge + NAT. Safe to re-run (rewrites our block only).
create_lab_network() {
  require_root; require_pve
  local br="$SOC_BRIDGE" gw="$SOC_GATEWAY" prefix="$SOC_NETMASK"
  local cidr="${SOC_SUBNET}.0/${prefix}"

  # Refuse to touch a bridge that already exists and isn't ours.
  if grep -qE "^[[:space:]]*(auto|iface)[[:space:]]+${br}\b" "$SOC_IF_FILE" 2>/dev/null \
     && ! grep -q "easy-deploy-SOC" "$SOC_IF_FILE" 2>/dev/null; then
    die "Bridge ${br} already exists in ${SOC_IF_FILE} and wasn't created by us.
     Pick a free bridge via SOC_LAB_BRIDGE (e.g. vmbr9) or use SOC_NET_MODE=existing."
  fi

  ensure_cmd iptables
  local wan; wan="$(wan_interface)"
  if [[ "$SOC_NET_NAT" == "1" && -z "$wan" ]]; then
    msg_warn "No default route on the host; the lab won't reach the internet."
    msg_warn "Provisioning steps that download packages/agents will fail."
  fi

  msg_info "Configuring isolated lab bridge ${br} (${gw}/${prefix})${wan:+, NAT via ${wan}}"

  # Back up once, then rewrite our managed block.
  [[ -f "${SOC_IF_FILE}.soc.bak" ]] || cp -a "$SOC_IF_FILE" "${SOC_IF_FILE}.soc.bak" 2>/dev/null || true
  _strip_net_block

  {
    echo ""
    echo "$SOC_NET_BEGIN"
    echo "auto ${br}"
    echo "iface ${br} inet static"
    echo "    address ${gw}/${prefix}"
    echo "    bridge-ports none"
    echo "    bridge-stp off"
    echo "    bridge-fd 0"
    if [[ "$SOC_NET_NAT" == "1" && -n "$wan" ]]; then
      echo "    post-up   sysctl -w net.ipv4.ip_forward=1"
      echo "    post-up   iptables -t nat -A POSTROUTING -s ${cidr} ! -d ${cidr} -o ${wan} -j MASQUERADE"
      echo "    post-down iptables -t nat -D POSTROUTING -s ${cidr} ! -d ${cidr} -o ${wan} -j MASQUERADE"
      echo "    post-up   iptables -A FORWARD -i ${br} -o ${wan} -j ACCEPT"
      echo "    post-down iptables -D FORWARD -i ${br} -o ${wan} -j ACCEPT"
      echo "    post-up   iptables -A FORWARD -i ${wan} -o ${br} -m state --state RELATED,ESTABLISHED -j ACCEPT"
      echo "    post-down iptables -D FORWARD -i ${wan} -o ${br} -m state --state RELATED,ESTABLISHED -j ACCEPT"
    fi
    echo "$SOC_NET_END"
  } >> "$SOC_IF_FILE"

  _apply_net
  msg_ok "Lab network ${br} is up. Gateway ${gw}/${prefix}${wan:+, NAT out ${wan}}."
  state_set SOC_NET_BRIDGE "$br"
}

# Remove the lab bridge and NAT rules we added.
destroy_lab_network() {
  require_root
  local br="${SOC_NET_BRIDGE:-$SOC_BRIDGE}"
  if ! grep -q "easy-deploy-SOC" "$SOC_IF_FILE" 2>/dev/null; then
    msg_warn "No easy-deploy-SOC network block found in ${SOC_IF_FILE}; nothing to remove."
    return 0
  fi
  msg_info "Removing lab bridge ${br} and its NAT rules"
  ifdown "$br" 2>/dev/null || true
  _strip_net_block
  _apply_net
  ip link delete "$br" 2>/dev/null || true
  msg_ok "Lab network ${br} removed."
}
