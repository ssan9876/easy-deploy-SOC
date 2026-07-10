# Usage

## Deploy

On the Proxmox host shell, as root:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ssan9876/easy-deploy-SOC/main/soc-deploy.sh)"
```

Choose **Deploy the FULL SOC lab**, confirm the summary, and walk away. Or deploy
pieces one at a time from the menu / the scripts in `scripts/`.

Want your own passwords? Open **Configure** first — it prompts for the Windows
admin and lab-user passwords (or set `SOC_ADMIN_PASSWORD` / `SOC_USER_PASSWORD`).
Leave them blank to have strong ones generated.

### Rough timings

| Phase | Time |
|-------|------|
| VMs created and started | seconds |
| Ubuntu boxes reachable over SSH | 2–5 min |
| Wazuh all-in-one install finishes | 10–15 min |
| Windows unattended install | 10–20 min each |
| DC promotion + reboots | +5–10 min |
| Client domain join + agent install | +5–10 min after the DC is up |

Deploy order for the full lab is SIEM → DC → Linux → client, so the DC exists by
the time the client boots and tries to join. The client retries the join for
~15 minutes, which covers a still-finishing DC.

## Getting in

Credentials are on the Proxmox host at `/var/lib/easy-deploy-soc/lab.env`.

```bash
cat /var/lib/easy-deploy-soc/lab.env
```

- **RDP** to the DC (`10.0.0.10`) and client (`10.0.0.20`) as
  `Administrator` / `SOC_ADMIN_PASSWORD` (DC) or `labadmin` (client). After the
  join, log into the client with `SOCLAB\Administrator` too.
- **SSH** to the analyst box (`10.0.0.30`) and SIEM (`10.0.0.40`) as
  `analyst` / `SOC_USER_PASSWORD`. The analyst box is **Kali with an XFCE
  desktop** — open its Proxmox console (it auto-logs into the desktop) or RDP to
  `10.0.0.30`.
- **Wazuh dashboard**: `https://10.0.0.40` as `admin`. The generated admin
  password is on the SIEM VM at `/root/WAZUH-CREDENTIALS.txt`.

> **Reaching Wazuh from your own PC.** In the default isolated network the lab
> lives on its own `10.0.0.0/24` bridge (`vmbr9`) your workstation can't route
> to. The deployer publishes the dashboard on the Proxmox host, so browse to
> `https://<proxmox-host-ip>:8443` (change the port with
> `SOC_SIEM_PUBLISH_PORT`, disable with `SOC_PUBLISH_SIEM=0`, or add/adjust it
> later from the **Publish** menu action). To reach the *other* lab IPs, connect
> from the Proxmox host (on `10.0.0.1`), use the VM consoles in the Proxmox UI,
> or add a route to `10.0.0.0/24` via the Proxmox host.

Confirm telemetry is flowing under **Wazuh → Agents** — you should see
`soc-dc01`, `soc-win11`, and `soc-linux01` reporting.

## Practice scenarios

The lab ships with data sources wired up so you can jump straight to detection
engineering and hunting:

- **Kerberoasting** — there's a service account (`svc_sql`). Request its ticket
  from the analyst box and crack it offline; hunt the 4769 events in Wazuh.
- **Over-privileged account** — `helpdesk` is (deliberately) in Domain Admins.
  Find it with `ldapsearch`/BloodHound and build a detection for the escalation.
- **Lateral movement** — authenticate from the client to the DC and watch the
  logon telemetry (Sysmon + Windows Security channel) land in the SIEM.
- **Recon** — `nmap`, `smbclient`, and `ldapsearch` from `soc-linux01` generate
  network/enumeration signal to alert on.

Add your own agents (extra clients, servers) by re-running the client deploy with
different `SOC_CLIENT_NAME` / `SOC_CLIENT_IP` / `SOC_CLIENT_VMID` values.

## Teardown

Menu **Destroy**, or:

```bash
./scripts/destroy-lab.sh
```

This stops and deletes every VM recorded in the state file and removes the
generated answer ISOs and cloud-init snippets.
