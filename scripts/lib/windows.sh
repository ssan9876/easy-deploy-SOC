#!/usr/bin/env bash
# windows.sh — build a Windows VM wired for unattended install.
# Requires core.sh, config.sh, proxmox.sh already sourced.

# Create + start a Windows VM.
# Args (named via env for clarity):
#   VMID NAME OSTYPE CORES RAM DISK STORAGE BRIDGE VLAN
#   WIN_ISO VIRTIO_ISO ANSWER_ISO  (Proxmox volume ids)
build_windows_vm() {
  local vmid="$1" name="$2" ostype="$3" cores="$4" ram="$5" disk="$6"
  local storage="$7" bridge="$8" vlan="$9"
  local win_iso="${10}" virtio_iso="${11}" answer_iso="${12}"

  if vm_exists "$vmid"; then
    die "VMID ${vmid} already exists. Choose a different SOC_VMID_BASE or remove it."
  fi

  local net="e1000,bridge=${bridge}"
  [[ -n "$vlan" ]] && net="${net},tag=${vlan}"

  msg_info "Creating Windows VM ${vmid} (${name})"
  qm create "$vmid" \
    --name "$name" \
    --ostype "$ostype" \
    --machine q35 \
    --bios ovmf \
    --cpu host \
    --sockets 1 --cores "$cores" \
    --memory "$ram" \
    --scsihw virtio-scsi-single \
    --net0 "$net" \
    --agent enabled=1 \
    --tablet 1 \
    --vga std \
    || die "qm create failed for ${vmid}"

  # UEFI vars + TPM (Win11 requirement; DC benefits too).
  qm set "$vmid" --efidisk0 "${storage}:1,efitype=4m,pre-enrolled-keys=0" >/dev/null \
    || die "Failed to add EFI disk to ${vmid}"
  qm set "$vmid" --tpmstate0 "${storage}:1,version=v2.0" >/dev/null \
    || die "Failed to add TPM to ${vmid}"

  # OS disk on SATA so Setup needs no injected storage driver.
  qm set "$vmid" --sata0 "${storage}:${disk}" >/dev/null \
    || die "Failed to add OS disk to ${vmid}"

  # Three CD-ROMs: Windows install, VirtIO drivers/tools, generated answer ISO.
  qm set "$vmid" --ide0 "${win_iso},media=cdrom" >/dev/null
  qm set "$vmid" --ide1 "${virtio_iso},media=cdrom" >/dev/null
  qm set "$vmid" --ide2 "${answer_iso},media=cdrom" >/dev/null

  # Boot the Windows ISO first; after install, Windows' own UEFI boot entry wins.
  qm set "$vmid" --boot "order=ide0;sata0" >/dev/null

  qm set "$vmid" --description "easy-deploy-SOC ${name} — unattended install in progress" >/dev/null

  msg_ok "Configured VM ${vmid} (${name})"
  msg_info "Starting ${name}; unattended Windows install will run now."
  qm start "$vmid" || die "Failed to start ${vmid}"
  nudge_boot_from_cd "$vmid"
  msg_ok "${name} started (VMID ${vmid}). Watch it in the Proxmox console."
}

# Tap a key past the UEFI "Press any key to boot from CD or DVD..." prompt so the
# unattended install starts with nobody at the console. Microsoft's install media
# shows that prompt on every boot from the CD; without a keypress the firmware
# gives up on the optical drive and falls through to the still-empty system disk,
# reporting "no bootable media" — so the install never begins.
#
# The prompt only appears while the CD still outranks the disk in the boot order
# (i.e. the first boot, before Windows is on the disk). We tap Enter for a bounded
# window that comfortably covers the prompt but ends well inside WinPE's file-copy
# phase, long before the first reboot — so later "press any key" prompts correctly
# time out and boot the freshly-installed Windows instead of restarting Setup.
nudge_boot_from_cd() { # vmid
  local vmid="$1" end
  command -v qm >/dev/null 2>&1 || return 0
  end=$(( $(date +%s) + 120 ))
  (
    while [[ $(date +%s) -lt $end ]]; do
      qm sendkey "$vmid" ret >/dev/null 2>&1 || true
      sleep 3
    done
  ) &
  msg_info "Auto-tapping the boot prompt so Setup starts hands-off (VMID ${vmid})."
}
