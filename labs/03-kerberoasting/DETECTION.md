# Lab 03 — Kerberoasting: what it leaves behind

**ATT&CK:** T1558.003 (Kerberoasting).

## What the attacker did
As any authenticated user, requested a Kerberos service ticket (TGS) for
`svc_sql` (which has an SPN). The ticket is encrypted with the service account's
NTLM hash, so it can be **cracked offline** — no further contact with the DC.

## Why it matters
- **Any** domain user can do it — no admin rights needed.
- The crack happens **off the network**, so the only detection opportunity is the
  ticket *request* at the moment it happens.
- Weak service-account passwords (like the planted `Summer2025!`) fall in seconds.

## The one signal you get
| Event | Meaning |
|-------|---------|
| `4769` | Kerberos service ticket requested — the core Kerberoasting signal |

A single `4769` is completely normal (it happens constantly). Kerberoasting is
distinguished by **context**:
- **Ticket Encryption Type `0x17` (RC4/HMAC)** — modern clients use AES (`0x12`).
  A request downgraded to RC4 is a classic roasting tell.
- **Service Name** = a user account's SPN (like `MSSQLSvc/...`) rather than a
  computer account (`$`).
- **Volume** — one account requesting tickets for many SPNs quickly.
- `Failure Code 0x0` (success) from an unusual workstation.

## Detection logic to build
Alert on `4769` where **all** of:
- `TicketEncryptionType` = `0x17`, and
- `ServiceName` does **not** end in `$` (i.e. targets a user SPN), and
- `TargetUserName`/requestor isn't a known service host.

Then add a volume rule: one requestor pulling many distinct SPNs in a short time.

## Hardening you can then verify
- Give `svc_sql` a long random password (25+ chars) or make it a **gMSA** — then
  re-run the lab and watch the crack fail. That's the fix, demonstrated.
- Enforce AES; disable RC4 where possible.

## Wazuh
Filter `agent.name: soc-dc01` and `data.win.system.eventID: 4769`; add columns for
`data.win.eventdata.ticketEncryptionType` and `data.win.eventdata.serviceName`.
The RC4 request for `svc_sql` from your analyst host stands out.

A starter rule is in `labs/detections/local_rules.xml`
(`SOC lab: possible Kerberoasting (RC4 TGS for a user SPN)`).
