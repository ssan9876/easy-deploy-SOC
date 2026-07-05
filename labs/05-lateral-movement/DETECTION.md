# Lab 05 — Lateral movement: what it leaves behind

**ATT&CK:** T1021.002 (SMB/Windows Admin Shares), T1569.002 (Service Execution),
T1047 (WMI), T1078.002 (Valid Domain Accounts).

## What the attacker did
Used compromised privileged creds (the planted `helpdesk` Domain Admin) to run
code on a remote host — psexec-style (temporary service) and/or wmiexec-style
(WMI).

## This is where defenders win
Unlike recon, execution is **loud**. Each technique has a distinct fingerprint.

### psexec (service execution)
| Event | Meaning |
|-------|---------|
| `4624` type 3 | Network logon with the admin creds |
| `4672` | Special privileges assigned (admin logon) |
| `5140` | Admin share (`ADMIN$`/`C$`) accessed |
| `7045` | **Service installed** — often a random 8-char name |
| `4697` | Service installed (Security log, if audited) |
| Sysmon `1` | Process create: the service binary, then `cmd.exe`/your command |

### wmiexec (WMI execution)
| Event | Meaning |
|-------|---------|
| `4624` type 3 + `4672` | Network admin logon |
| Sysmon `1` | **`WmiPrvSE.exe` spawning `cmd.exe`** — the tell (no `7045`) |
| `4688` | Process creation with `WmiPrvSE.exe` as parent |

## Detection logic to build
1. **Suspicious service install** — `7045` where the service name looks random
   (high entropy / matches known-tool patterns) or the image path is in a temp
   dir → high severity.
2. **WMI process ancestry** — Sysmon `1` where `ParentImage` ends in
   `WmiPrvSE.exe` and `Image` is a shell (`cmd.exe`, `powershell.exe`).
3. **Admin logon from a workstation** — `4624`/`4672` for a privileged account
   sourced from a host that shouldn't be initiating admin sessions (your analyst
   box). Baseline which hosts legitimately do admin.

## Wazuh
- `agent.name: soc-win11` + `data.win.system.eventID: (7045 OR 4697)` for psexec.
- Sysmon: `data.win.system.channel: "Microsoft-Windows-Sysmon/Operational"` with
  `data.win.eventdata.parentImage` containing `WmiPrvSE.exe` for wmiexec.

Starter rules for both are in `labs/detections/local_rules.xml`.

## The lesson
Run psexec, wmiexec, and smbexec against the same target and diff the logs. Good
detection engineering means covering the **technique**, not one tool — your rules
should catch all three ways in.
