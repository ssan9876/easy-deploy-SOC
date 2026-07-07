# Incident Report — [Incident ID / short name]

> Blank template. Fill it in from your Wazuh reconstruction of Lab 06. Write the
> **Executive Summary last**, once the details are nailed down. Keep it factual;
> mark anything you're inferring as an assumption.

| Field | Value |
|-------|-------|
| Incident ID | |
| Analyst | |
| Date/time of report (UTC) | |
| Severity | Low / Medium / High / **Critical** |
| Status | Investigating / Contained / Eradicated / Closed |
| Classification | e.g. Credential Access → Domain Compromise |

---

## 1. Executive summary
*3–5 sentences a manager can read. What happened, how bad, what's the impact, what
you're doing about it. No jargon.*



## 2. Timeline of events (UTC)
*The spine of the report. One row per meaningful event, in order. Cite the source
event ID/log so it's defensible.*

| Time (UTC) | Host | Account | Event ID | ATT&CK | Description |
|-----------|------|---------|----------|--------|-------------|
| | | | | | |
| | | | | | |
| | | | | | |

## 3. Initial access / entry point
*How the attacker first got in. First compromised account and the technique.*



## 4. What the attacker did (attack narrative)
*Prose walkthrough of the intrusion, phase by phase, mapped to ATT&CK.*

- **Reconnaissance (T1046 / T1087):**
- **Initial access (T1110.003):**
- **Credential access (T1558.003):**
- **Privilege use (T1078.002):**
- **Lateral movement (T1021.002):**
- **Impact / domain dominance (T1003.006):**

## 5. Scope & impact (blast radius)
*Which systems, accounts, and data are affected. What must now be treated as
compromised? (After a `krbtgt` DCSync, justify why the answer is the whole domain.)*



## 6. Indicators of Compromise (IOCs)
| Type | Value | Notes |
|------|-------|-------|
| Source host/IP | | attacker foothold |
| Account(s) | | compromised / abused |
| Service name | | e.g. suspicious 7045 service |
| SPN targeted | | Kerberoast |

## 7. Detection gaps
*Which phases did you NOT see, or see late? What data source or rule would have
caught them? (This is the most valuable section for improving the SOC.)*



## 8. Containment
*Immediate actions to stop the bleeding — disable accounts, isolate hosts, block
the source. What did you do / recommend, and in what order?*



## 9. Eradication & recovery
*Remove attacker access and restore trust. For this scenario include the specific
AD fixes and note that a `krbtgt` compromise requires a **double krbtgt password
reset**. Then how you verified clean.*



## 10. Root cause & remediation
*The misconfigurations that made this possible and the durable fixes.*

| Root cause | Fix | Verified? |
|-----------|-----|-----------|
| `svc_sql` weak password + SPN | Long random pw / gMSA; enforce AES | |
| `helpdesk` in Domain Admins | Remove; least privilege / tiering | |
| RC4 Kerberos allowed | Disable RC4 where possible | |

## 11. Lessons learned
*What worked, what didn't, and the concrete improvements to detections, logging,
and process. Turn each detection gap from §7 into an action item with an owner.*


