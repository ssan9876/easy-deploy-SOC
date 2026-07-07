# Lab 06 — Hunt guide: reconstruct the intrusion

You just ran a full attack. Now be the analyst. Your job: **rebuild the timeline
from Wazuh alone** and figure out what happened, in what order, to which assets.
Work the questions before looking at the answer key (`GROUND-TRUTH.txt`).

Everything below is done in Wazuh → **Discover** on `soc-wazuh01`
(`https://10.0.0.40`). Set the time range to the last hour.

## Ground rules for a good reconstruction
- Anchor on **time** — build a chronological story, not a pile of alerts.
- For each event capture: **when, source host/IP, account, target, technique**.
- Distinguish the **attacker's origin** (one IP recurs — that's patient zero's
  foothold) from the **assets touched**.

## Work the phases (don't peek at the answer key)

### 1. Find the earliest suspicious activity
- [ ] Filter `agent.name: soc-dc01`. Scroll to the earliest anomalies.
- [ ] Is there an `ANONYMOUS LOGON` / type-3 logon from an internal host that
      isn't a server? Note that IP — it likely recurs all the way through.

### 2. Initial access
- [ ] Search `data.win.system.eventID: (4768 OR 4771)`. Do you see **many
      accounts** hit from **one source** in seconds? (password spray)
- [ ] Which account produced a **success** right after the failures? That's the
      compromised foothold.

### 3. Credential access
- [ ] Search `data.win.system.eventID: 4769`. Filter/inspect
      `data.win.eventdata.ticketEncryptionType`. Find the **`0x17` (RC4)** request
      and its `serviceName`. Which SPN account was Kerberoasted?

### 4. Privileged logon
- [ ] Search `data.win.system.eventID: (4624 OR 4672)` for a **Domain Admin**
      account logging on to the DC (type 3) from that same foothold IP. When?

### 5. Lateral movement
- [ ] Filter `agent.name: soc-win11`. Find `data.win.system.eventID: 7045` (a new
      service, often a random name) and the accompanying type-3 logon.
- [ ] In Sysmon, look for the service binary / `cmd.exe` process-create.

### 6. Domain dominance (the climax)
- [ ] Search `data.win.system.eventID: 4662` on `soc-dc01`. Look for an access to
      a directory object involving the **replication** rights
      (`DS-Replication-Get-Changes`). That's **DCSync** — the attacker pulled
      secrets (incl. `krbtgt`). This is the most severe event in the whole chain.

## Build your timeline
Fill a table like this (this becomes the spine of your report):

| Time (UTC) | Host | Account | Event ID | Technique | What it means |
|-----------|------|---------|----------|-----------|---------------|
| … | soc-dc01 | — | 4771 ×N | T1110.003 | password spray |
| … | … | … | … | … | … |

## Answer the incident questions
1. What was the **entry point** (first account compromised) and how?
2. What was the **attacker's source host**?
3. Which **assets** were accessed (DC, client)?
4. What was the **most severe** action and why?
5. What is the **blast radius** — what should now be considered compromised?
   (Hint: after DCSync of `krbtgt`, the answer is "the entire domain.")
6. What **three misconfigurations** made this possible?

## Grade yourself
Now open `GROUND-TRUTH.txt` and compare. Did you catch every phase? Which one was
hardest to see, and what data source would have made it obvious? Write that down —
it's your detection-gap list.

## Detection coverage check
For each phase, did a rule from `../detections/local_rules.xml` fire? If DCSync
didn't alert, add the `4662` replication rule (also in that file) and re-run.
