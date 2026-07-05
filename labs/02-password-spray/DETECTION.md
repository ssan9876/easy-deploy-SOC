# Lab 02 — Password spraying: what it leaves behind

**ATT&CK:** T1110.003 (Brute Force: Password Spraying).

## What the attacker did
Tried a single common password (`Summer2025!`) against every account, via
Kerberos pre-authentication (kerbrute).

## The signature
One source authenticating against **many different accounts** in a **short
window** — the inverse of a brute force (many passwords vs one account). This
shape is what you alert on, not any single failure.

| Event | Meaning | Where |
|-------|---------|-------|
| `4768` | Kerberos TGT (AS-REQ) requested | DC Security log |
| `4771` | Kerberos pre-auth failed (bad password) — `Failure Code 0x18` | DC |
| `4776` | NTLM credential validation (if NTLM path) | DC |
| `4625` | Failed logon | DC / target |
| `4740` | Account lockout (if you tripped the policy) | DC |

A **hit** looks like a `4768` success with no matching `4771` failure for that
account — i.e. the spray password worked.

## Detection logic to build
- **Threshold + correlation:** ≥ N distinct `TargetUserName` values with `4771`
  (or `4625`) from the **same** `IpAddress` within M minutes → alert.
- In Wazuh this is a **frequency rule** using `<frequency>` and `<same_source_ip>`
  / `<different_...>` fields, or an aggregation over `data.win.eventdata.ipAddress`.
- Watch for the follow-on **success** (`4768` with Result Code 0x0) right after a
  wave of failures from that IP — that's the compromised account.

## Wazuh
Filter `agent.name: soc-dc01` and `data.win.system.eventID: (4768 OR 4771 OR 4776)`.
Group by source IP over time; your analyst IP (10.0.0.30) hitting five accounts in
seconds is unmistakable.

A starter frequency rule is in `labs/detections/local_rules.xml`
(`SOC lab: possible password spray`).

## Tuning
Real environments have noisy accounts (expired passwords, bad service configs).
Baseline normal failure rates first, then set your threshold above the noise.
