#!/usr/bin/env bash
# common.sh — shared setup for the hands-on attack labs. Run these FROM the
# analyst box (soc-linux01). Everything here targets your isolated lab only.
#
# Override any target with an env var, e.g. DC_IP=10.0.0.10 ./run.sh

# --- Lab targets (match scripts/lib/config.sh defaults) ---------------------
: "${DOMAIN:=soclab.local}"
: "${NETBIOS:=SOCLAB}"
: "${DC_HOST:=soc-dc01}"
: "${DC_IP:=10.0.0.10}"
: "${CLIENT_IP:=10.0.0.20}"
: "${SIEM_IP:=10.0.0.40}"
# shellcheck disable=SC2034  # used by sourcing lab scripts (e.g. 01-enumeration)
DOMAIN_DN="$(echo "$DOMAIN" | sed 's/\./,DC=/g; s/^/DC=/')"   # soclab.local -> DC=soclab,DC=local

# Credentials you use for authenticated steps. Provide a low-priv domain user
# you know (any of the lab users), e.g.:  LAB_USER=jsmith LAB_PASS='...'
: "${LAB_USER:=}"
: "${LAB_PASS:=}"

# --- Output helpers ----------------------------------------------------------
if [[ -t 1 ]]; then C_G=$'\033[1;92m'; C_Y=$'\033[33m'; C_B=$'\033[36m'; C_R=$'\033[1;31m'; C_D=$'\033[2m'; C_0=$'\033[m'
else C_G=''; C_Y=''; C_B=''; C_R=''; C_D=''; C_0=''; fi
say()  { echo -e "${C_B}▸${C_0} $*"; }
ok()   { echo -e "${C_G}✓${C_0} $*"; }
warn() { echo -e "${C_Y}!${C_0} $*"; }
err()  { echo -e "${C_R}✗ $*${C_0}" >&2; }
step() { echo -e "\n${C_B}━━ $* ━━${C_0}"; }
hunt() { echo -e "\n${C_Y}🔎 Now hunt it:${C_0} $*"; }

# --- Safety guard ------------------------------------------------------------
confirm_lab() {
  echo -e "${C_D}Target: ${DOMAIN} / DC ${DC_IP} / client ${CLIENT_IP}${C_0}"
  warn "Only run this against your own isolated SOC lab."
  if [[ "${LAB_ASSUME_YES:-0}" != "1" ]]; then
    read -r -p "Proceed? [y/N] " a; [[ "$a" =~ ^[Yy] ]] || { echo "Aborted."; exit 1; }
  fi
}

need_creds() {
  if [[ -z "$LAB_USER" || -z "$LAB_PASS" ]]; then
    warn "This lab needs valid domain creds (any user works)."
    read -r -p "Domain username: " LAB_USER
    read -r -s -p "Password: " LAB_PASS; echo
  fi
}

# --- Tool installers (idempotent) -------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

apt_install() { sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" >/dev/null 2>&1; }

ensure_pipx() {
  have pipx && return 0
  say "Installing pipx..."
  sudo apt-get update -qq >/dev/null 2>&1 || true
  apt_install pipx python3-venv || return 1
  pipx ensurepath >/dev/null 2>&1 || true
  export PATH="$HOME/.local/bin:$PATH"
}

ensure_impacket() {
  have impacket-GetUserSPNs && return 0
  ensure_pipx || return 1
  say "Installing Impacket (this can take a minute)..."
  pipx install impacket >/dev/null 2>&1 || pipx install impacket
  export PATH="$HOME/.local/bin:$PATH"
  have impacket-GetUserSPNs || { err "Impacket install failed."; return 1; }
  ok "Impacket ready"
}

ensure_kerbrute() {
  have kerbrute && return 0
  say "Installing kerbrute..."
  local url="https://github.com/ropnop/kerbrute/releases/latest/download/kerbrute_linux_amd64"
  if curl -fsSL "$url" -o /tmp/kerbrute 2>/dev/null; then
    sudo install -m 0755 /tmp/kerbrute /usr/local/bin/kerbrute && ok "kerbrute ready" && return 0
  fi
  err "Could not download kerbrute. Check the lab's internet (NAT) access."; return 1
}

ensure_hashcat() { have hashcat && return 0; say "Installing hashcat..."; apt_install hashcat && ok "hashcat ready"; }
ensure_nmap()    { have nmap    && return 0; apt_install nmap; }
ensure_ldap()    { have ldapsearch && return 0; apt_install ldap-utils; }
ensure_smb()     { have smbclient  && return 0; apt_install smbclient; }

ensure_rockyou() {
  ROCKYOU=/usr/share/wordlists/rockyou.txt
  [[ -f "$ROCKYOU" ]] && { echo "$ROCKYOU"; return 0; }
  apt_install wordlists >/dev/null 2>&1 || true
  [[ -f "${ROCKYOU}.gz" ]] && sudo gunzip -kf "${ROCKYOU}.gz" 2>/dev/null || true
  [[ -f "$ROCKYOU" ]] && { echo "$ROCKYOU"; return 0; }
  return 1
}

# A small users list used across labs.
LAB_USERS_LIST() { printf '%s\n' administrator jsmith awong svc_sql helpdesk; }
