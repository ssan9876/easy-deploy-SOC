# Hands-on labs

Guided attack exercises that turn the roadmap in [`../docs/LEARNING.md`](../docs/LEARNING.md)
into muscle memory. Each lab **runs an attack from the analyst box**, then a
`DETECTION.md` tells you exactly what it left behind and how to detect it in
Wazuh. The whole point is the loop: **attack → observe → detect → tune.**

> ⚠️ Run these against **your own isolated lab only** (the walled-off
> `10.0.0.0/24`). These are real offensive tools.

## Where to run them

- **The `run.sh` scripts:** from the **analyst box** (`soc-linux01`, SSH in as
  `analyst`). They auto-install what they need (impacket, kerbrute, hashcat) via
  the lab's NAT internet access.
- **`04-asrep-roasting/setup-on-dc.ps1`:** on the **DC** (PowerShell as admin) —
  it plants the misconfig that lab then exploits.
- **`detections/local_rules.xml`:** on the **Wazuh manager** (`soc-wazuh01`).

## Get the labs onto the analyst box

```bash
git clone https://github.com/ssan9876/easy-deploy-SOC
cd easy-deploy-SOC/labs
```

## The labs

| # | Lab | ATT&CK | Runs end-to-end? |
|---|-----|--------|------------------|
| 01 | [Enumeration](01-enumeration/) | T1046, T1087, T1069 | Yes (recon is meant to feel "quiet") |
| 02 | [Password spraying](02-password-spray/) | T1110.003 | Yes |
| 03 | [Kerberoasting](03-kerberoasting/) | T1558.003 | **Yes — cracks `svc_sql`** |
| 04 | [AS-REP roasting](04-asrep-roasting/) | T1558.004 | After `setup-on-dc.ps1` |
| 05 | [Lateral movement](05-lateral-movement/) | T1021, T1569, T1047 | Yes (with admin creds) |

Suggested order: **01 → 02 → 03 → 04 → 05** — it mirrors a real intrusion
(discover → get a foothold → escalate → move).

## Running a lab

```bash
# Some labs need domain creds — any lab user works. Provide them inline:
LAB_USER=jsmith LAB_PASS='<the lab user password>' ./03-kerberoasting/run.sh

# Skip the confirmation prompt for automation:
LAB_ASSUME_YES=1 ./01-enumeration/run.sh
```

Lab user passwords are in `/var/lib/easy-deploy-soc/lab.env` on the Proxmox host
(`SOC_USER_PASSWORD`). The planted **weak** service password for `svc_sql` is
`SOC_WEAK_SVC_PASSWORD` (default `Summer2025!`) — that's what makes lab 03 crack.

Override targets with env vars if you changed the defaults:
`DC_IP`, `CLIENT_IP`, `DOMAIN`, `DC_HOST`, `SIEM_IP`.

## The planted weaknesses (so the labs have something to find)

- **`helpdesk`** is in **Domain Admins** → privilege-escalation & lateral-movement
  target (labs 01, 05).
- **`svc_sql`** has an **SPN** and a **weak password** → Kerberoasting target that
  actually cracks (lab 03).
- **AS-REP roasting** (lab 04) requires you to plant its own weakness first, on
  purpose — a lesson that some attacks only work against misconfigurations.

## After every lab

1. Open the matching `DETECTION.md`.
2. Find the events in Wazuh (*Discover*, filter by agent + event ID).
3. Install/adapt the rule from `detections/local_rules.xml` and prove it fires.
4. Write it in your notebook: command, events, rule, MITRE ID, false positives.

## Install the detection rules

On `soc-wazuh01`:

```bash
sudo nano /var/ossec/etc/rules/local_rules.xml   # paste the rules from detections/
sudo /var/ossec/bin/wazuh-logtest                # sanity-check decoding
sudo systemctl restart wazuh-manager
```

Then re-run the labs and confirm your rules light up. Treat the shipped rules as
**starting points** — the field names and thresholds are exactly what you should
be verifying and tuning against real events.

## Cleanup

These labs write hash/output files next to their `run.sh` and may create a
temporary service on the target (psexec cleans up after itself). To reset the
whole lab to a known-good state, restore the Proxmox snapshots you took in
Phase 0.
