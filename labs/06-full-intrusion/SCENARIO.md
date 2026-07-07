# Lab 06 — Full intrusion: the scenario

This capstone chains the individual techniques into one coherent incident, the way
a real intrusion unfolds. You run it once, then switch hats and work it as the
defender: **reconstruct → report → remediate.**

## The story

An attacker with a foothold on the network (your analyst box, `10.0.0.30`) works
from zero to full domain compromise:

1. **Reconnaissance** (T1046, T1087) — scans the DC and client, probes SMB.
2. **Initial access** (T1110.003) — password-sprays a weak seasonal password and
   lands on the `svc_sql` service account.
3. **Credential access** (T1558.003) — Kerberoasts an SPN account and cracks the
   ticket offline.
4. **Privilege use** (T1078.002) — authenticates to the DC as the over-privileged
   `helpdesk` (Domain Admin) account.
5. **Lateral movement** (T1021.002) — executes code on the workstation via SMB +
   a temporary service (psexec-style).
6. **Domain dominance** (T1003.006) — performs a **DCSync**, replicating secrets
   (including `krbtgt`) straight from the DC. Game over.

## The ATT&CK chain

```
Recon ─▶ Initial Access ─▶ Credential Access ─▶ Privilege Use ─▶ Lateral ─▶ Impact
T1046     T1110.003          T1558.003            T1078.002        T1021.002  T1003.006
```

## Honesty note (this matters for learning)

A truly self-driving zero-to-DA chain needs a real escalation primitive that's
fiddly to plant reliably. So step 4 **uses the `helpdesk` Domain Admin creds you
supply** (from `lab.env`) to represent "the attacker obtained the
over-privileged account." That account is genuinely over-privileged in this lab —
finding it was Lab 01. Everything the chain then does (DA logon, lateral movement,
DCSync) generates **real, authentic telemetry**, which is the whole point for the
blue-team exercise. In a real engagement you'd chain another technique (ACL abuse,
a second Kerberoast, token theft) to get there.

## How to run

From the analyst box:

```bash
cd easy-deploy-SOC/labs/06-full-intrusion
DA_PASS='<helpdesk password from lab.env SOC_USER_PASSWORD>' ./run.sh
# Optional: PACING=30 spaces the acts further apart for a cleaner timeline;
#           PACING=0 runs them back to back.
```

The run writes an **answer key** to `GROUND-TRUTH.txt` — a timestamped list of
every act and the events it should have produced. **Don't open it** until you've
reconstructed the incident yourself.

## Then work it as the defender

1. **Hunt & reconstruct** — [`HUNT-GUIDE.md`](HUNT-GUIDE.md).
2. **Report** — [`INCIDENT-REPORT-TEMPLATE.md`](INCIDENT-REPORT-TEMPLATE.md).
3. **Grade yourself** — diff your timeline against `GROUND-TRUTH.txt`.
4. **Remediate & verify** — apply the fixes (strong `svc_sql` password/gMSA,
   remove `helpdesk` from Domain Admins, enforce AES), then re-run and watch
   steps fail.
5. **Reset** — restore your Phase-0 Proxmox snapshots.
