# SOC Homelab Learning Path

A start-to-finish roadmap for turning this lab into real SOC / blue-team skill.
Work top to bottom — each phase builds on the last. Tick the boxes as you go.

**Golden rule:** every attack technique here is for **your own isolated lab
only**. That's the whole point of the walled-off `10.0.0.0/24` network.

**How to use this:** for every offensive action you run from the analyst box,
immediately go find it in Wazuh. The loop *attack → observe → detect → tune* is
the entire job. Don't just run tools; explain what each one left behind.

Lab quick reference:

| Box | IP | Role |
|-----|----|------|
| `soc-dc01` | 10.0.0.10 | Domain Controller + DNS (`soclab.local`) |
| `soc-win11` | 10.0.0.20 | Domain-joined workstation |
| `soc-linux01` | 10.0.0.30 | Analyst / attacker box |
| `soc-wazuh01` | 10.0.0.40 | Wazuh SIEM (`https://10.0.0.40`) |

Deliberately-weak things planted for you to find: user `helpdesk` is in **Domain
Admins** (privilege-escalation target), and `svc_sql` is a **service account with
an SPN** (Kerberoasting target).

---

## Phase 0 — Orientation & baseline

- [ ] Confirm all four VMs are running and the three agents (`soc-dc01`,
      `soc-win11`, `soc-linux01`) show **Active** in Wazuh → *Agents*.
- [ ] RDP into the DC and the client; SSH into the analyst box and the SIEM.
- [ ] Draw the network yourself from memory: who talks to whom, who's the gateway,
      who resolves DNS. Confirm it against `docs/ARCHITECTURE.md`.
- [ ] Take a **Proxmox snapshot of every VM** and label it `clean-baseline`. You
      will break things on purpose — this is your undo button.
- [ ] Find the credentials file on the Proxmox host: `/var/lib/easy-deploy-soc/lab.env`.
- [ ] In Wazuh, open the *Security Events* dashboard and just watch normal traffic
      for 10 minutes. Get a feel for "quiet."

## Phase 1 — Foundations you can't skip

**Active Directory**
- [ ] Learn the vocabulary: forest, domain, OU, user, group, GPO, DNS, Kerberos,
      NTLM, LDAP. Be able to explain each in a sentence.
- [ ] On the DC, open *Active Directory Users and Computers* and explore the
      `SOCLab` OU. Note who's a member of Domain Admins — is anything wrong?
- [ ] Create a user and a group in the GUI, then do the same in PowerShell
      (`New-ADUser`, `New-ADGroup`, `Add-ADGroupMember`).
- [ ] Create and link a simple GPO (e.g. a logon banner) and force `gpupdate` on
      the client.

**Windows logging (the raw material of a SOC)**
- [ ] Open *Event Viewer* on the DC and client. Find the **Security** log and the
      **Microsoft-Windows-Sysmon/Operational** log.
- [ ] Memorize the greatest-hits event IDs and what each means:
      `4624` logon, `4625` failed logon, `4634` logoff, `4672` special
      privileges, `4688` process creation, `4720` user created, `4728/4732/4756`
      added to group, `4768` TGT requested, `4769` service ticket requested,
      `4776` NTLM auth, `7045` service installed.
- [ ] Learn Windows **logon types** (2 interactive, 3 network, 10 RDP, etc.) and
      why they matter for hunting.
- [ ] Read one good Sysmon event of each type: process create (ID 1), network
      connect (ID 3), image load (ID 7), file create (ID 11), registry (ID 13).

**Wazuh / SIEM fundamentals**
- [ ] Understand the pipeline: **agent → decoder → rule → alert → dashboard**.
- [ ] Find where rules live on the manager: `/var/ossec/etc/rules/` and the
      ruleset in `/var/ossec/ruleset/`. Read a few built-in rules.
- [ ] Learn the alert **levels** (0–15) and what severity means.
- [ ] Run a search in the dashboard (Discover) filtered to one agent and one
      event ID. Save it.

**Frameworks**
- [ ] Skim the **MITRE ATT&CK** matrix. Bookmark it. From now on, tag everything
      you do with a technique ID (e.g. Kerberoasting = T1558.003).
- [ ] Learn the **Pyramid of Pain** — why hash/IP indicators are weak and
      behavior/TTP detections are strong.

## Phase 2 — Generate telemetry & read it (blue basics)

- [ ] On the client, log off and mistype the password 5 times. Find the `4625`
      events in Wazuh. What fields identify the source?
- [ ] RDP into the client from the analyst box (or another host). Find the
      logon-type-10 `4624`.
- [ ] Create a user on the DC and add them to a privileged group. Find `4720` and
      `4728/4732`. This is your first "insider" signal.
- [ ] Run `whoami`, `net user`, `net group "Domain Admins" /domain` on the client
      and correlate the `4688`/Sysmon ID 1 process-creation events.
- [ ] For each of the above, write one sentence: *"An attacker doing X would
      generate event Y."*

## Phase 3 — Offense from the analyst box (feed the blue side)

Do each attack, **then** hunt it in Wazuh and note the detection opportunity.

> 🧪 **Guided versions of everything below live in [`../labs/`](../labs/)** — each
> lab runs the attack from the analyst box and ships a `DETECTION.md` with the
> exact events + a Wazuh rule to write. Start there if you'd rather run than read.

**Recon / enumeration** (T1046, T1087, T1069)
- [ ] `nmap -sV -p- 10.0.0.10` and `10.0.0.20`. What's exposed?
- [ ] SMB: `smbclient -L //10.0.0.10 -N`; install and run `enum4linux-ng`.
- [ ] LDAP: `ldapsearch -x -H ldap://10.0.0.10 -b "dc=soclab,dc=local"` — dump
      users, find `helpdesk` in Domain Admins and `svc_sql`'s SPN.
- [ ] Detect: which of these are noisy in the logs, and which are nearly silent?
      (Recon is the hardest thing to catch — understand why.)

**Password attacks** (T1110)
- [ ] Password-spray a common password across users with `nxc`/`crackmapexec`
      (`nxc smb 10.0.0.10 -u users.txt -p 'Season2025!'`).
- [ ] Build a Wazuh detection for many `4625`/`4776` across accounts from one
      source in a short window. Tune out the false positives.

**Kerberos attacks** (T1558)
- [ ] **Kerberoast** `svc_sql`: request its service ticket
      (`impacket-GetUserSPNs` or Rubeus), crack the hash offline with
      `hashcat -m 13100`.
- [ ] **AS-REP roast** any account with pre-auth disabled (set one up to practice).
- [ ] Detect: find the `4769` ticket request with RC4 encryption. Write a rule.
      Understand why this is high-signal.

**Privilege escalation / lateral movement** (T1078, T1021, T1550)
- [ ] Use the `helpdesk` (Domain Admin) creds you discovered to authenticate to
      the DC. Watch the `4624` type-3 + `4672`.
- [ ] Try `impacket-psexec`/`wmiexec` from the analyst box to the client and
      catch the `7045` service install / process creation.
- [ ] Optional: install **BloodHound** + SharpHound, collect the domain, and let
      it draw you the shortest path to Domain Admin. Compare to what you found by
      hand.

## Phase 4 — Detection engineering

- [ ] Write your **first custom Wazuh rule** in `local_rules.xml` (e.g. alert when
      anyone is added to Domain Admins) and prove it fires.
- [ ] Tune **Sysmon**: read the SwiftOnSecurity config already deployed, then add
      an exclusion and a new inclusion; redeploy and confirm the change.
- [ ] Learn **Sigma**: write one Sigma rule, then convert it and port the logic
      into a Wazuh rule. Understand detection-as-code.
- [ ] For 5 techniques you ran in Phase 3, write a proper detection each and
      record: data source, logic, MITRE ID, false-positive notes, severity.
- [ ] Measure your own coverage: which ATT&CK techniques can you now detect vs.
      which slipped through silently?

## Phase 5 — Threat hunting

- [ ] Learn hypothesis-driven hunting (start with a hypothesis, not a tool).
- [ ] Hunt for **persistence**: new services (`7045`), scheduled tasks, run keys,
      new local admins. Plant one, then hunt it.
- [ ] Hunt for **lateral movement**: unusual type-3 logons, `svchost` spawning
      cmd, admin shares.
- [ ] Hunt for **living-off-the-land**: `powershell -enc`, `certutil` downloads,
      `rundll32`, `mshta`. Generate each and find it.
- [ ] Write up one hunt as a mini-report: hypothesis, data, findings, verdict.

## Phase 6 — Incident response

> 🎯 **The capstone lab [`../labs/06-full-intrusion/`](../labs/06-full-intrusion/)
> is built for this phase.** It runs a full recon→foothold→Kerberoast→DA→lateral→
> DCSync chain, then hands you a `HUNT-GUIDE.md` to reconstruct it and a blank
> `INCIDENT-REPORT-TEMPLATE.md` to write it up — with a `GROUND-TRUTH.txt` answer
> key to grade yourself against.

- [ ] Learn the IR lifecycle (**PICERL**: Prep, Identify, Contain, Eradicate,
      Recover, Lessons-learned) or the NIST 4-phase model.
- [ ] Run the capstone (or your own scenario): from the analyst box, "compromise"
      the domain (initial access → Kerberoast → DA → lateral → DCSync), leaving
      natural artifacts.
- [ ] As the analyst: **detect** it in Wazuh, **build a timeline** of what
      happened and when, **identify** patient zero and blast radius.
- [ ] Practice containment (disable account, isolate host) and eradication, then
      **restore from your Proxmox snapshot** and confirm clean.
- [ ] Write an incident report: executive summary, timeline, IOCs, ATT&CK
      mapping, remediation, lessons learned.

## Phase 7 — Level up (extend the lab)

- [ ] **Atomic Red Team** — run atomics to systematically test detection coverage.
- [ ] **MITRE Caldera** or **Prelude** — automated adversary emulation.
- [ ] **Velociraptor** — endpoint DFIR / live hunting across hosts.
- [ ] Add a second Windows client, a member server, or a Linux web server to
      widen the attack surface (re-run the client deploy with new name/IP/VMID).
- [ ] Ship **PowerShell Script Block Logging** (4104) and module logging; hunt on
      it.
- [ ] Route firewall/pfSense or Suricata/Zeek network telemetry into Wazuh for
      network-side detections.
- [ ] Purple-team a full ATT&CK technique: emulate, detect, tune, document —
      repeat until the detection is solid.

---

## Cross-cutting habits (do these the whole way through)

- [ ] Keep an **engineering notebook**: every attack, the exact command, the
      events it produced, and the detection you wrote. This becomes your portfolio.
- [ ] Tag everything with **MITRE ATT&CK** technique IDs.
- [ ] After each phase, snapshot a "known-good" state so you can always reset.
- [ ] Re-run an attack a week later and see if your detection still fires — that's
      how you learn detection decay.

## Suggested study companions

- **Concepts/labs:** TryHackMe (SOC Level 1 path), Blue Team Labs Online,
  LetsDefend, Splunk BOTS datasets.
- **Reading:** MITRE ATT&CK site, The DFIR Report (real intrusions, mapped),
  Microsoft's Windows security event ID reference, Wazuh docs, HackTricks (AD
  section) for the offensive side.
- **Certs to aim at (optional, roughly in order):** CompTIA Security+ → CySA+ or
  **Blue Team Level 1 (BTL1)** → GCIH/GCIA if you go pro.

## Milestones — you'll know it's working when you can…

1. Explain, from memory, what happens in the logs during a normal domain logon.
2. Kerberoast `svc_sql`, crack it, and show the exact `4769` that gave it away.
3. Write a Wazuh rule from scratch that fires on a technique you chose.
4. Take a raw alert and pivot to a full attack timeline.
5. Produce an incident report a manager could actually read.
