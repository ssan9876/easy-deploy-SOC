#!/usr/bin/env bash
# linux.sh — build an Ubuntu cloud-init VM from a rendered user-data snippet.
# Requires core.sh, config.sh, proxmox.sh already sourced.

# Args:
#   VMID NAME CORES RAM DISK STORAGE BRIDGE VLAN IP NAMESERVER
#   IMG_PATH SNIPPET_VOL
build_linux_vm() {
  local vmid="$1" name="$2" cores="$3" ram="$4" disk="$5"
  local storage="$6" bridge="$7" vlan="$8" ip="$9" nameserver="${10}"
  local img="${11}" snippet_vol="${12}"

  if vm_exists "$vmid"; then
    die "VMID ${vmid} already exists. Choose a different VMID or remove it."
  fi

  local net="virtio,bridge=${bridge}"
  [[ -n "$vlan" ]] && net="${net},tag=${vlan}"

  msg_info "Creating Linux VM ${vmid} (${name})"
  qm create "$vmid" \
    --name "$name" \
    --ostype l26 \
    --machine q35 \
    --cpu host \
    --sockets 1 --cores "$cores" \
    --memory "$ram" \
    --scsihw virtio-scsi-single \
    --net0 "$net" \
    --agent enabled=1 \
    --serial0 socket --vga serial0 \
    || die "qm create failed for ${vmid}"

  # Import the cloud image straight onto scsi0 (Proxmox 7.2+ import-from).
  qm set "$vmid" --scsi0 "${storage}:0,import-from=${img}" >/dev/null \
    || die "Failed to import cloud image for ${vmid}"
  qm disk resize "$vmid" scsi0 "${disk}G" >/dev/null 2>&1 \
    || qm resize "$vmid" scsi0 "${disk}G" >/dev/null 2>&1 || true

  # Cloud-init drive + network + custom user-data.
  qm set "$vmid" --ide2 "${storage}:cloudinit" >/dev/null
  qm set "$vmid" --boot "order=scsi0" >/dev/null
  qm set "$vmid" --ipconfig0 "ip=${ip}/${SOC_NETMASK},gw=${SOC_GATEWAY}" >/dev/null
  qm set "$vmid" --nameserver "$nameserver" >/dev/null
  qm set "$vmid" --cicustom "user=${snippet_vol}" >/dev/null
  qm set "$vmid" --description "easy-deploy-SOC ${name}" >/dev/null

  msg_ok "Configured VM ${vmid} (${name})"
  qm start "$vmid" || die "Failed to start ${vmid}"
  msg_ok "${name} started (VMID ${vmid}); cloud-init is provisioning it."
}

# Render a cloud-init template to the snippet storage; echo its volume id.
# Args: template basename VAR=val ...
install_snippet() {
  local tpl="$1" base="$2"; shift 2
  local st; st="$(resolve_snippet_storage)"
  local dir; dir="$(snippet_storage_path "$st")"
  mkdir -p "$dir"
  render_template "$tpl" "${dir}/${base}" "$@"
  echo "${st}:snippets/${base}"
}

# Password hash for cloud-init users.
pw_hash() { openssl passwd -6 "$1"; }
