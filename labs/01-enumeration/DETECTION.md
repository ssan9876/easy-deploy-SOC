# Lab 01 — Enumeration: what it leaves behind

**ATT&CK:** T1046 (Network Service Discovery), T1087.002 (Domain Account
Discovery), T1069.002 (Domain Group Discovery), T1018 (Remote System Discovery).

## What the attacker did
Port-scanned the DC, tried a null SMB session, and (with a low-priv account)
enumerated users, SPNs, and Domain Admins over LDAP.

## What you can see — and the hard truth
Recon is the **hardest phase to detect** because most of it looks like normal
network activity. This is a deliberately humbling first lab.

| Action | Telemetry | Realistic to alert on? |
|--------|-----------|------------------------|
| nmap port scan | Firewall/flow logs, many short connections | Only with network sensors (Suricata/Zeek/pfSense) — not in default Windows logs |
| SMB null session | `4624` logon type 3 (ANONYMOUS LOGON), `5140` share access | Yes, but noisy |
| LDAP queries | `4624` type 3 from the analyst IP; with **Directory Service** auditing, `1644` | Low-signal; huge FP surface |
| Authenticated bind | `4624` type 3 for the account used | Baseline it |

**Key lesson:** you rarely catch recon directly. You catch it in *aggregate*
(one host touching many services/accounts fast) or you catch the **next** step.
This is why defense-in-depth and behavioral baselines matter.

## Detection ideas to build
1. **ANONYMOUS LOGON to the DC** — alert on `4624` where `TargetUserName` =
   `ANONYMOUS LOGON` and `LogonType` = 3. (Tune: some legacy apps do this.)
2. **One source, many accounts** — a single source IP generating type-3 logons
   for many distinct accounts in a short window (correlation rule).
3. **Enable network visibility** — this lab is the argument for adding
   Suricata/Zeek or pfSense logs into Wazuh (see roadmap Phase 7). A `-p-` nmap
   scan is trivial to see at the network layer and invisible at the host layer.

## Wazuh
Look in *Discover*, filter `agent.name: soc-dc01` and `data.win.system.eventID: 4624`.
Add a column for `data.win.eventdata.logonType` and `ipAddress`. Watch your own
analyst IP (10.0.0.30) light up as you run the lab.

A starter custom rule for anonymous logons is in `labs/detections/local_rules.xml`.
