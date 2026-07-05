# Lab 04 — AS-REP roasting: what it leaves behind

**ATT&CK:** T1558.004 (AS-REP Roasting).

## What the attacker did
Requested authentication data for accounts that have **"do not require Kerberos
pre-authentication"** set. For those accounts the DC returns an AS-REP encrypted
with the account's password hash — **crackable offline, no credentials required**.

## Why it matters
Even more dangerous than Kerberoasting because it needs **no valid account** — an
unauthenticated attacker who knows (or guesses) usernames can try it. It only
works against misconfigured accounts, which is why the lab has you create the
condition on purpose.

## The signal
| Event | Meaning |
|-------|---------|
| `4768` | TGT requested — but with **Pre-Authentication Type = 0 (none)** |

Legitimate Kerberos logons **always** pre-authenticate, so a `4768` with
`PreAuthType = 0` is a strong, low-false-positive indicator.

## Detection logic to build
Alert on `4768` where `PreAuthType` = `0`. Optionally join to a list of accounts
that are *supposed* to have pre-auth disabled (should be empty) so any hit pages.

Also **preventive detection**: periodically query AD for
`userAccountControl` containing `DONT_REQ_PREAUTH` (flag `0x400000`) and alert on
any account that shouldn't have it — catch the misconfig before it's abused.

## Wazuh
Filter `agent.name: soc-dc01` and `data.win.system.eventID: 4768`; add a column
for `data.win.eventdata.preAuthType` and alert on value `0`.

A starter rule is in `labs/detections/local_rules.xml`
(`SOC lab: AS-REP roasting (no Kerberos pre-auth)`).

## Fix, then verify
On the DC: `Set-ADAccountControl -Identity jsmith -DoesNotRequirePreAuth $false`,
re-run the lab, and confirm there's nothing left to roast.
