#!/usr/bin/env bash
# Lab 01 — Recon & enumeration of the domain from the analyst box.
# MITRE ATT&CK: T1046, T1087.002, T1069.002, T1018
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/../lib/common.sh"

echo "== Lab 01: Enumeration =="
confirm_lab
ensure_nmap; ensure_smb; ensure_ldap

step "Port / service scan of the DC (T1046)"
say "nmap of common AD ports — note 88(Kerberos) 389/636(LDAP) 445(SMB) 3389(RDP)"
nmap -Pn -sV -p 53,88,135,139,389,445,464,636,3268,3389 "$DC_IP"

step "SMB — null session enumeration (T1087)"
say "Anonymous share listing (modern AD usually blocks this — that itself is a finding):"
smbclient -L "//${DC_IP}" -N 2>&1 | head -n 20 || true

step "LDAP — domain object enumeration (T1087.002 / T1069.002)"
if [[ -n "$LAB_USER" && -n "$LAB_PASS" ]]; then
  BASE="$DOMAIN_DN"
  say "Authenticated LDAP as ${LAB_USER}. Listing users:"
  ldapsearch -x -H "ldap://${DC_IP}" -D "${LAB_USER}@${DOMAIN}" -w "$LAB_PASS" \
    -b "$BASE" "(objectClass=user)" sAMAccountName 2>/dev/null \
    | grep -i '^sAMAccountName:' | sort -u

  step "Find accounts with a Service Principal Name (Kerberoast targets)"
  say "Any user with an SPN can be Kerberoasted (see lab 03):"
  ldapsearch -x -H "ldap://${DC_IP}" -D "${LAB_USER}@${DOMAIN}" -w "$LAB_PASS" \
    -b "$BASE" "(&(objectClass=user)(servicePrincipalName=*))" sAMAccountName servicePrincipalName 2>/dev/null \
    | grep -iE '^(sAMAccountName|servicePrincipalName):'

  step "Find members of Domain Admins (privilege targets)"
  ldapsearch -x -H "ldap://${DC_IP}" -D "${LAB_USER}@${DOMAIN}" -w "$LAB_PASS" \
    -b "$BASE" "(&(objectClass=group)(cn=Domain Admins))" member 2>/dev/null \
    | grep -i '^member:'
  warn "See an unexpected account in Domain Admins? That's the planted 'helpdesk' weakness."
else
  warn "No creds provided (LAB_USER/LAB_PASS). AD blocks anonymous LDAP, so the"
  warn "authenticated steps are skipped. Re-run with e.g. LAB_USER=jsmith LAB_PASS=..."
fi

hunt "In Wazuh, filter to agent soc-dc01. Recon is deliberately quiet — see 01-enumeration/DETECTION.md for what IS visible (SMB/LDAP session events, 4624 type 3) and why recon is the hardest phase to catch."
ok "Lab 01 complete."
