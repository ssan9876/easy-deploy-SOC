#!/usr/bin/env bash
# core.sh — shared helpers for the easy-deploy-SOC toolkit.
# Sourced by every deploy script. No side effects on source beyond defining
# functions and (optionally) colors.

# ---------------------------------------------------------------------------
# Colors / output helpers
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  RD=$'\033[01;31m'; GN=$'\033[1;92m'; YW=$'\033[33m'; BL=$'\033[36m'
  DM=$'\033[2m'; CL=$'\033[m'
else
  RD=''; GN=''; YW=''; BL=''; DM=''; CL=''
fi
CM="${GN}✓${CL}"; CROSS="${RD}✗${CL}"; INFO="${BL}➤${CL}"

# All status messages go to stderr so command substitutions that capture a
# helper's stdout (e.g. x="$(resolve_iso_volume ...)") only get the real value.
msg_info()  { echo -e " ${INFO} ${DM}$*${CL}" >&2; }
msg_ok()    { echo -e " ${CM} $*" >&2; }
msg_warn()  { echo -e " ${YW}!${CL} $*" >&2; }
msg_error() { echo -e " ${CROSS} ${RD}$*${CL}" >&2; }

# Fatal error: print and exit non-zero.
die() { msg_error "$*"; exit 1; }

# Print a banner. Arg1 = subtitle.
banner() {
  echo -e "${BL}"
  cat <<'EOF'
   ____  ___  ____    _  _  ___  __  __ ___ _      _   ___
  / ___|/ _ \/ ___|  | || |/ _ \|  \/  | __| |    /_\ | _ )
  \___ \ (_) \___ \  | __ | (_) | |\/| | _|| |__ / _ \| _ \
  |____/\___/|____/  |_||_|\___/|_|  |_|___|____/_/ \_\___/
EOF
  echo -e "${CL}${DM}  easy-deploy-SOC  •  ${1:-Proxmox SOC homelab deployer}${CL}\n"
}

# ---------------------------------------------------------------------------
# Environment guards
# ---------------------------------------------------------------------------
require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "This script must be run as root (on the Proxmox host)."
}

require_pve() {
  if ! command -v qm >/dev/null 2>&1 || ! command -v pvesh >/dev/null 2>&1; then
    die "Proxmox VE tools (qm/pvesh) not found. Run this on a Proxmox VE host."
  fi
  local ver
  ver="$(pveversion 2>/dev/null | grep -oP 'pve-manager/\K[0-9]+' | head -n1)"
  if [[ -n "$ver" && "$ver" -lt 7 ]]; then
    msg_warn "Detected Proxmox VE major version $ver. Tested on 7.x/8.x; continuing anyway."
  fi
}

# Ensure a host command exists, installing it via apt if missing.
ensure_cmd() {
  local cmd="$1" pkg="${2:-$1}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    msg_info "Installing missing dependency: $pkg"
    apt-get update -qq >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" >/dev/null 2>&1 \
      || die "Failed to install '$pkg'. Install it manually and re-run."
    msg_ok "Installed $pkg"
  fi
}

# ---------------------------------------------------------------------------
# whiptail wrappers (fall back to plain prompts when whiptail is absent)
# ---------------------------------------------------------------------------
HAS_WHIPTAIL=0
command -v whiptail >/dev/null 2>&1 && HAS_WHIPTAIL=1

wt_input() { # title, prompt, default -> echoes value
  local title="$1" prompt="$2" default="$3" out
  if [[ "$HAS_WHIPTAIL" -eq 1 ]]; then
    out="$(whiptail --title "$title" --inputbox "$prompt" 10 70 "$default" 3>&1 1>&2 2>&3)" \
      || return 1
  else
    read -r -p "$prompt [$default]: " out
    out="${out:-$default}"
  fi
  echo "$out"
}

wt_password() { # title, prompt -> echoes value
  local title="$1" prompt="$2" out
  if [[ "$HAS_WHIPTAIL" -eq 1 ]]; then
    out="$(whiptail --title "$title" --passwordbox "$prompt" 10 70 3>&1 1>&2 2>&3)" || return 1
  else
    read -r -s -p "$prompt: " out; echo >&2
  fi
  echo "$out"
}

wt_yesno() { # title, prompt -> return 0 for yes
  local title="$1" prompt="$2" ans
  if [[ "$HAS_WHIPTAIL" -eq 1 ]]; then
    whiptail --title "$title" --yesno "$prompt" 12 70
  else
    read -r -p "$prompt [y/N]: " ans
    [[ "$ans" =~ ^[Yy] ]]
  fi
}

wt_menu() { # title, prompt, then pairs: tag description ... -> echoes chosen tag
  local title="$1" prompt="$2"; shift 2
  if [[ "$HAS_WHIPTAIL" -eq 1 ]]; then
    whiptail --title "$title" --menu "$prompt" 20 76 10 "$@" 3>&1 1>&2 2>&3
  else
    local i=1 tags=() ; echo "$prompt" >&2
    while [[ $# -gt 0 ]]; do
      tags+=("$1"); echo "  $i) $1 — $2" >&2; shift 2; ((i++))
    done
    local sel; read -r -p "Choose [1]: " sel; sel="${sel:-1}"
    echo "${tags[$((sel-1))]}"
  fi
}

# Multi-select checklist -> echoes space-separated chosen tags (quoted stripped)
wt_checklist() { # title, prompt, then triples: tag description on/off ...
  local title="$1" prompt="$2"; shift 2
  if [[ "$HAS_WHIPTAIL" -eq 1 ]]; then
    whiptail --title "$title" --checklist "$prompt" 20 76 10 "$@" 3>&1 1>&2 2>&3 \
      | tr -d '"'
  else
    local out=()
    while [[ $# -gt 0 ]]; do
      local tag="$1" desc="$2" state="$3"; shift 3
      local def="n"; [[ "$state" == "ON" ]] && def="y"
      local ans; read -r -p "Include $tag ($desc)? [${def}]: " ans
      ans="${ans:-$def}"; [[ "$ans" =~ ^[Yy] ]] && out+=("$tag")
    done
    echo "${out[*]}"
  fi
}

# ---------------------------------------------------------------------------
# Misc helpers
# ---------------------------------------------------------------------------
# Generate a random strong-ish password if none provided.
random_password() {
  local p
  p="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 14)"
  echo "Soc-${p}!"
}

# XML-escape a string so it is safe to embed in an autounattend.xml value.
xml_escape() {
  local s="$1"
  s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"
  s="${s//\"/&quot;}"; s="${s//\'/&apos;}"
  printf '%s' "$s"
}

# Set (create or update) a single KEY='value' line in the state file without
# disturbing any other keys. Safe for values with sed-special chars.
state_set() { # key value
  mkdir -p "$SOC_STATE_DIR"
  local f="${SOC_STATE_DIR}/lab.env" k="$1" v="$2" tmp
  touch "$f"
  tmp="$(mktemp)"
  grep -v "^${k}=" "$f" > "$tmp" 2>/dev/null || true
  printf "%s='%s'\n" "$k" "$v" >> "$tmp"
  ( umask 077; mv "$tmp" "$f" )
}

# Resolve lab passwords with precedence: explicit env var > saved state > generated.
# Persists them to $SOC_STATE_DIR/lab.env (0600) so every component agrees.
init_lab_secrets() {
  mkdir -p "$SOC_STATE_DIR"
  local f="${SOC_STATE_DIR}/lab.env"
  local env_admin="${SOC_ADMIN_PASSWORD:-}" env_user="${SOC_USER_PASSWORD:-}"
  # shellcheck disable=SC1090
  [[ -f "$f" ]] && source "$f"
  [[ -n "$env_admin" ]] && SOC_ADMIN_PASSWORD="$env_admin"
  [[ -n "$env_user"  ]] && SOC_USER_PASSWORD="$env_user"
  [[ -z "${SOC_ADMIN_PASSWORD:-}" ]] && SOC_ADMIN_PASSWORD="$(random_password)"
  [[ -z "${SOC_USER_PASSWORD:-}"  ]] && SOC_USER_PASSWORD="$(random_password)"
  state_set SOC_ADMIN_PASSWORD "$SOC_ADMIN_PASSWORD"
  state_set SOC_USER_PASSWORD "$SOC_USER_PASSWORD"
  export SOC_ADMIN_PASSWORD SOC_USER_PASSWORD
}

# Replace @@KEY@@ placeholders in a file using a name=value map file.
# Usage: render_template <template> <output> <VAR1=val1> <VAR2=val2> ...
render_template() {
  local tpl="$1" dst="$2"; shift 2
  cp "$tpl" "$dst"
  local pair k v
  for pair in "$@"; do
    k="${pair%%=*}"; v="${pair#*=}"
    # Escape sed-special chars in the value.
    v="$(printf '%s' "$v" | sed -e 's/[\/&|]/\\&/g')"
    sed -i "s|@@${k}@@|${v}|g" "$dst"
  done
}
