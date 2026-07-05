# easy-deploy-SOC

**One-line SOC (Security Operations Center) homelab deployer for Proxmox VE.**

Run a single command on your Proxmox host and get a complete, self-contained
Active Directory + SIEM lab to practice blue-team / red-team skills on — in the
same spirit as the [Proxmox VE Helper-Scripts](https://community-scripts.github.io/ProxmoxVE/).

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ssan9876/easy-deploy-SOC/main/soc-deploy.sh)"
```

A whiptail menu walks you through it. Pick **Deploy the FULL SOC lab** and the
script builds everything below, unattended.

---

## What it builds

| VM | OS | Role | Default IP |
|----|----|------|-----------|
| `soc-dc01`   | Windows Server 2022 | **Domain Controller + DNS** — new forest `soclab.local` | `10.10.10.10` |
| `soc-win11`  | Windows 11          | **Domain-joined client** — Sysmon + Wazuh agent | `10.10.10.20` |
| `soc-linux01`| Ubuntu 22.04        | **Analyst / attacker box** — nmap, ldapsearch, smbclient, krb5 + Wazuh agent | `10.10.10.30` |
| `soc-wazuh01`| Ubuntu 22.04        | **Wazuh SIEM** (manager + indexer + dashboard) — collects logs from every endpoint | `10.10.10.40` |

```
                         ┌──────────────────────────┐
                         │  soc-wazuh01  (SIEM)      │
                         │  Wazuh dashboard :443     │◀── logs ──┐
                         └──────────────────────────┘           │
                                                                 │
   ┌───────────────┐     ┌───────────────┐     ┌────────────────┴─┐
   │  soc-dc01     │◀───▶│  soc-win11    │     │  soc-linux01     │
   │  DC + DNS     │ join│  domain client│     │  analyst/attacker│
   │  soclab.local │     │  Sysmon+agent │     │  Wazuh agent     │
   └───────────────┘     └───────────────┘     └──────────────────┘
        10.10.10.10          10.10.10.20            10.10.10.30
              all on bridge vmbr0 (optionally VLAN-tagged)
```

Everything is provisioned **hands-off**: Windows installs via `autounattend.xml`,
the DC promotes itself to a forest, the client waits for the DC and joins the
domain, and the Linux boxes configure themselves via cloud-init. Endpoints ship
Sysmon + Wazuh telemetry to the SIEM so you have data to hunt through on day one.

## Why these components

A realistic SOC lab needs three things: **an environment to attack/defend** (the
AD domain + client), **a place to generate and observe telemetry** (Sysmon on the
endpoints), and **a SIEM to centralize and alert on it** (Wazuh). The Linux box
gives you both an analyst workstation and an attacker foothold for generating
detections (Kerberoasting, SMB enumeration, lateral movement, etc.).

## Requirements

- **Proxmox VE 7.x or 8.x**, run the command as `root` on the host shell.
- Enough free resources for the full lab: **~10 vCPU, ~18 GB RAM, ~200 GB disk**
  (deploy components individually if that's tight).
- Outbound internet from the Proxmox host (to fetch ISOs, cloud images, agents).
- A storage that supports **Snippets** (for cloud-init) — enable it under
  *Datacenter → Storage → (your storage) → Edit → Content → Snippets*.

## Windows ISOs

The Windows VMs use Microsoft's **Evaluation** editions (Server 2022: 180 days,
Windows 11 Enterprise: 90 days) — free, no product key required. The script tries
to download them automatically, but **Microsoft's Evaluation Center links rotate
frequently**. If a download fails, the script lets you pick an ISO you've already
uploaded to your Proxmox ISO storage. To pre-seed them, download from the
Evaluation Center and upload via *Proxmox → your storage → ISO Images → Upload*,
then either name them to match or set the URL/name env vars (see below).

## Configuration

Every setting has a sane default and can be overridden with an environment
variable or through the menu's **Configure** screen. Common ones:

```bash
# Example: custom domain, subnet, VLAN, and storage
SOC_DOMAIN=corp.local \
SOC_SUBNET=192.168.50 \
SOC_GATEWAY=192.168.50.1 \
SOC_VLAN=50 \
SOC_STORAGE=local-lvm \
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ssan9876/easy-deploy-SOC/main/soc-deploy.sh)"
```

See [`scripts/lib/config.sh`](scripts/lib/config.sh) for the full list (IPs, VMIDs,
CPU/RAM/disk sizing, ISO URLs, agent versions).

## Credentials

Passwords are generated on first run and saved to **`/var/lib/easy-deploy-soc/lab.env`**
on the Proxmox host (mode `0600`). Set `SOC_ADMIN_PASSWORD` / `SOC_USER_PASSWORD`
to choose your own. The Wazuh dashboard admin password is written on the SIEM VM
at `/root/WAZUH-CREDENTIALS.txt` once its install finishes.

> Avoid a single-quote `'` in a custom password — it breaks the PowerShell
> string literals used during unattended setup. Other symbols are fine.

## Running individual pieces

You don't have to deploy everything at once — the menu (and the scripts under
[`scripts/`](scripts/)) let you build one component at a time:

```bash
git clone https://github.com/ssan9876/easy-deploy-SOC && cd easy-deploy-SOC
./scripts/deploy-siem.sh     # SIEM first
./scripts/deploy-dc.sh       # then the Domain Controller
./scripts/deploy-client.sh   # then the client (waits for the DC)
./scripts/deploy-linux.sh    # analyst box anytime
```

## Teardown

The menu's **Destroy** option (or `./scripts/destroy-lab.sh`) stops and deletes
every VM the toolkit created and cleans up generated answer ISOs / snippets.

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — how the automation works end to end.
- [docs/USAGE.md](docs/USAGE.md) — walkthrough, practice scenarios, timings.
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — when something doesn't come up.

## Safety & licensing notes

- **Keep this lab isolated.** It intentionally contains weak configurations
  (an over-privileged account, static creds) for practice. Don't expose it to a
  network you care about — use a dedicated bridge/VLAN and firewall it off.
- Windows runs on **Evaluation** licenses; they expire. Rebuild when they do.
- For authorized, educational security practice only.

## License

MIT — see [LICENSE](LICENSE).
