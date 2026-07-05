#!/usr/bin/env bash
# proxmox.sh — Proxmox-specific helpers (VMIDs, storage, ISO handling, VM checks).
# Requires core.sh + config.sh already sourced.

# Return the next free VMID at or above a given floor.
next_vmid() { # floor
  local floor="${1:-100}" id
  id="$(pvesh get /cluster/nextid 2>/dev/null || echo "$floor")"
  [[ "$id" -lt "$floor" ]] && id="$floor"
  while qm status "$id" >/dev/null 2>&1 || pct status "$id" >/dev/null 2>&1; do
    id=$((id + 1))
  done
  echo "$id"
}

vm_exists()   { qm status "$1" >/dev/null 2>&1; }

# List storages that support a given content type (images|iso|snippets|rootdir).
storages_supporting() { # content
  local content="$1"
  pvesm status -content "$content" 2>/dev/null | awk 'NR>1 {print $1}'
}

# Pick a VM-disk storage: honor SOC_STORAGE, else auto-pick first, else prompt.
resolve_disk_storage() {
  if [[ -n "$SOC_STORAGE" ]]; then echo "$SOC_STORAGE"; return; fi
  local -a opts=()
  while read -r s; do [[ -n "$s" ]] && opts+=("$s" "images storage"); done \
    < <(storages_supporting images)
  [[ ${#opts[@]} -eq 0 ]] && die "No storage supporting VM images found."
  if [[ ${#opts[@]} -eq 2 ]]; then echo "${opts[0]}"; return; fi
  wt_menu "Storage" "Select storage for VM disks:" "${opts[@]}"
}

# Where is an ISO storage mounted on the filesystem? (for building custom ISOs)
iso_storage_path() { # storage
  local st="$1" path
  path="$(pvesm path "${st}:iso/placeholder" 2>/dev/null | sed 's#/placeholder$##')"
  [[ -z "$path" ]] && path="/var/lib/vz/template/iso"
  echo "$path"
}

# Download a file into an ISO storage if not already present.
# Args: url filename storage
fetch_iso() {
  local url="$1" name="$2" storage="${3:-$SOC_ISO_STORAGE}"
  local dir; dir="$(iso_storage_path "$storage")"
  mkdir -p "$dir"
  local dest="${dir}/${name}"
  if [[ -f "$dest" ]]; then
    msg_ok "ISO already present: ${name}"
    echo "$dest"; return
  fi
  msg_info "Downloading ${name} ..."
  ensure_cmd curl
  if ! curl -fL# --retry 3 -o "${dest}.part" "$url"; then
    rm -f "${dest}.part"
    msg_error "Download failed for ${name}."
    msg_warn "Links from Microsoft's Evaluation Center rotate often."
    msg_warn "Upload the ISO to your '${storage}' storage manually and re-run,"
    msg_warn "or set SOC_*_ISO_URL to a working link."
    return 1
  fi
  mv "${dest}.part" "$dest"
  msg_ok "Downloaded ${name}"
  echo "$dest"
}

# Let the user pick an already-uploaded ISO from a storage (fallback path).
pick_existing_iso() { # storage, promptlabel
  local storage="$1" label="$2"
  local -a opts=()
  while read -r vol _; do
    [[ -z "$vol" ]] && continue
    opts+=("$vol" "${vol##*/}")
  done < <(pvesm list "$storage" -content iso 2>/dev/null | awk 'NR>1{print $1}')
  [[ ${#opts[@]} -eq 0 ]] && return 1
  wt_menu "Select ISO" "Pick the ISO for ${label}:" "${opts[@]}"
}

# Resolve an ISO: try download, and on failure fall back to interactive pick.
# Echoes a Proxmox volume id (storage:iso/name) usable in qm set.
resolve_iso_volume() { # url name label
  local url="$1" name="$2" label="$3"
  local path
  if path="$(fetch_iso "$url" "$name")"; then
    echo "${SOC_ISO_STORAGE}:iso/${name}"
    return 0
  fi
  local vol
  if vol="$(pick_existing_iso "$SOC_ISO_STORAGE" "$label")"; then
    echo "$vol"; return 0
  fi
  return 1
}

# Build a small ISO containing an autounattend.xml (+ helper scripts) and place
# it in the ISO storage. Windows Setup auto-detects autounattend.xml on any
# attached media. Echoes the resulting volume id.
build_answer_iso() { # srcdir volname
  local srcdir="$1" volname="$2"
  ensure_cmd genisoimage genisoimage
  local dir; dir="$(iso_storage_path "$SOC_ISO_STORAGE")"
  local dest="${dir}/${volname}"
  genisoimage -quiet -J -r -V "PROVISION" -o "$dest" "$srcdir" \
    || die "Failed to build answer ISO ${volname}"
  msg_ok "Built answer ISO ${volname}"
  echo "${SOC_ISO_STORAGE}:iso/${volname}"
}

# Filesystem path for a storage's snippets directory.
snippet_storage_path() { # storage
  local st="$1" path
  path="$(pvesm path "${st}:snippets/placeholder" 2>/dev/null | sed 's#/placeholder$##')"
  [[ -z "$path" ]] && path="/var/lib/vz/snippets"
  echo "$path"
}

# Pick a storage that supports snippets; fall back to the configured one.
resolve_snippet_storage() {
  local first
  first="$(storages_supporting snippets | head -n1)"
  if [[ -n "$first" ]]; then echo "$first"; return; fi
  msg_warn "No storage advertises 'snippets' content. Trying '${SOC_SNIPPET_STORAGE}'."
  msg_warn "If cloud-init fails, enable Snippets on a storage: Datacenter > Storage > Edit > Content."
  echo "$SOC_SNIPPET_STORAGE"
}

# Download a disk image (cloud image) to a local cache dir; echo its path.
fetch_cloud_image() { # url name
  local url="$1" name="$2"
  local cache="/var/lib/easy-deploy-soc/images"
  mkdir -p "$cache"
  local dest="${cache}/${name}"
  if [[ -f "$dest" ]]; then msg_ok "Cloud image cached: ${name}"; echo "$dest"; return; fi
  msg_info "Downloading cloud image ${name} ..."
  ensure_cmd curl
  curl -fL# --retry 3 -o "${dest}.part" "$url" || { rm -f "${dest}.part"; return 1; }
  mv "${dest}.part" "$dest"
  msg_ok "Downloaded ${name}"
  echo "$dest"
}

# Wait until a VM's qemu-guest-agent responds (best-effort, bounded).
wait_for_agent() { # vmid timeout_seconds
  local vmid="$1" timeout="${2:-600}" waited=0
  msg_info "Waiting for guest agent on VM ${vmid} (up to ${timeout}s)..."
  while (( waited < timeout )); do
    if qm agent "$vmid" ping >/dev/null 2>&1; then
      msg_ok "Guest agent responding on VM ${vmid}"
      return 0
    fi
    sleep 10; waited=$((waited + 10))
  done
  msg_warn "Guest agent did not respond on VM ${vmid} within ${timeout}s (install may still be running)."
  return 1
}
