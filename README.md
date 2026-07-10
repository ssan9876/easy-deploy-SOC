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

## Start here (newcomer path)

New to this? Follow it in order — deploy, learn the ground rules, drill each
attack, then run a full incident end to end.

1. **Deploy the lab.** Run the one-liner above on your Proxmox host and choose
   *Deploy the FULL SOC lab*. Wait for the Windows installs to finish (~20–30
   min). Grab your generated passwords from `/var/lib/easy-deploy-soc/lab.env`.
   → details in [docs/USAGE.md](docs/USAGE.md).
2. **Take a Proxmox snapshot of every VM** (label it `clean-baseline`). You'll
   break things on purpose; this is your reset button.
3. **Read the ground rules.** Skim [docs/LEARNING.md](docs/LEARNING.md) Phases 0–2
   to learn the attack→observe→detect loop and the key Windows event IDs.
4. **Confirm telemetry flows.** In the Wazuh dashboard (`https://10.0.0.40`),
   check that `soc-dc01`, `soc-win11`, and `soc-linux01` show as active agents.
5. **Run your first attack.** SSH to the analyst box and run
   [`labs/01-enumeration`](labs/), then hunt it in Wazuh with the lab's
   `DETECTION.md`. Work through labs 01 → 05.
6. **Run the capstone.** [`labs/06-full-intrusion`](labs/06-full-intrusion/)
   chains it all into one incident — reconstruct it and write it up with the
   included incident-report template.

Everything is safe to repeat: restore your snapshot and go again.

---

## What it builds

| VM | OS | Role | Default IP |
|----|----|------|-----------|
| `soc-dc01`   | Windows Server 2022 (**Desktop Experience / full GUI**) | **Domain Controller + DNS** — new forest `soclab.local` | `10.0.0.10` |
| `soc-win11`  | Windows 11          | **Domain-joined client** — Sysmon + Wazuh agent | `10.0.0.20` |
| `soc-linux01`| **Kali Linux** (XFCE desktop) | **Analyst / attacker box** — full Kali toolset + Wazuh agent | `10.0.0.30` |
| `soc-wazuh01`| Ubuntu 22.04        | **Wazuh SIEM** (manager + indexer + dashboard) — collects logs from every endpoint | `10.0.0.40` |

```
   Proxmox host ── vmbr9 (isolated) 10.0.0.1  ──▶ NAT ──▶ internet
        │
        ├── walled off from your existing LAN ──────────────────────┐
        │                                                            │
   ┌───────────────┐     ┌───────────────┐     ┌──────────────────┐ │
   │  soc-dc01     │◀───▶│  soc-win11    │     │  soc-linux01     │ │
   │  DC + DNS     │ join│  domain client│     │  analyst/attacker│ │
   │  soclab.local │     │  Sysmon+agent │     │  Wazuh agent     │ │
   └───────────────┘     └───────────────┘     └──────────────────┘ │
        10.0.0.10             10.0.0.20              10.0.0.30        │
        ┌──────────────────────────┐                                 │
        │  soc-wazuh01  (SIEM)      │◀────────── logs ────────────────┘
        │  Wazuh dashboard :443     │   10.0.0.40
        └──────────────────────────┘
```

Everything is provisioned **hands-off**: Windows installs via `autounattend.xml`
(the DC installs the **Desktop Experience** GUI edition, not Server Core), the DC
promotes itself to a forest, the client waits for the DC and joins the domain, and
the Linux boxes configure themselves via cloud-init — the analyst box comes up as
**Kali Linux with an XFCE desktop** and the full toolset. Endpoints ship Sysmon +
Wazuh telemetry to the SIEM so you have data to hunt through on day one.

### Reaching the Wazuh dashboard from your own PC

The lab lives on an isolated subnet your workstation can't route to. So you can
still open the SIEM, the deployer (in the default isolated mode) publishes a
**port-forward on the Proxmox host**: browse to
`https://<proxmox-host-ip>:8443` and it lands on the SIEM's `:443`. Change the
port with `SOC_SIEM_PUBLISH_PORT`, or turn the forward off with
`SOC_PUBLISH_SIEM=0`. The **Configure** menu also asks, and there's a
**Publish** menu action to add it to an already-running lab.

### Desktops & remote access (RDP from your own PC)

All three desktop VMs come up with RDP enabled (the Windows boxes via their
answer files, Kali via `xrdp`). But the lab lives on an isolated subnet your
workstation can't route to — so, exactly like the Wazuh dashboard, the deployer
(in the default isolated mode) **publishes each desktop's RDP on the Proxmox
host**. Point Remote Desktop at the host IP on these ports:

| Connect to | Lands on | Default login |
|-----------|----------|---------------|
| `<proxmox-host-ip>:13389` | `soc-dc01` (Windows Server desktop) | `Administrator` |
| `<proxmox-host-ip>:23389` | `soc-win11` (Windows 11 client) | `labadmin` |
| `<proxmox-host-ip>:33389` | `soc-linux01` (Kali XFCE desktop) | `analyst` |

(On Windows `mstsc`, put e.g. `192.168.88.4:13389` in the Computer field; other
clients take the host and port separately. Passwords are in
`/var/lib/easy-deploy-soc/lab.env`.) The exact map is also printed at the end of
a deploy and by the menu's **Info** action.

- Change the host ports with `SOC_RDP_DC_PORT` / `SOC_RDP_CLIENT_PORT` /
  `SOC_RDP_LINUX_PORT`, or turn the forwards off with `SOC_PUBLISH_RDP=0` (the
  desktops then remain reachable only from inside the lab subnet or the Proxmox
  console). The **Publish** menu action adds the forwards to an already-running
  lab.
- On the lab subnet directly, RDP straight to `10.0.0.10` / `10.0.0.20` /
  `10.0.0.30`. Set `SOC_LINUX_DESKTOP=0` for a headless Kali box instead.
- These ports are exposed on the Proxmox host's LAN interface, guarded only by
  the VM passwords — fine for a trusted homelab. In `SOC_NET_MODE=existing` no
  host forward is added; publish RDP on your own router/firewall instead.

## Why these components

A realistic SOC lab needs three things: **an environment to attack/defend** (the
AD domain + client), **a place to generate and observe telemetry** (Sysmon on the
endpoints), and **a SIEM to centralize and alert on it** (Wazuh). The Linux box
gives you both an analyst workstation and an attacker foothold for generating
detections (Kerberoasting, SMB enumeration, lateral movement, etc.).

## Networking — the lab gets its own isolated network

By default (`SOC_NET_MODE=isolated`) the deployer creates a **dedicated private
bridge** (`vmbr9`) on the Proxmox host for a `10.0.0.0/24` lab network, walled
off from your existing LAN:

- The **Proxmox host is the lab's gateway** at `10.0.0.1`, and **NATs** the lab
  out to the internet (so provisioning — package installs, Wazuh, agent
  downloads — still works) while nothing on your home/office network can reach
  the lab and vice-versa.
- DNS is self-contained: the DC (`10.0.0.10`) serves `soclab.local` and forwards
  internet lookups to an upstream resolver (`1.1.1.1` by default).
- The bridge is written to `/etc/network/interfaces` behind clearly-marked
  `# BEGIN/END easy-deploy-SOC` lines and applied with `ifreload` — your existing
  interfaces are left untouched, and the teardown removes it cleanly.

Prefer to use a bridge/router you already run? Set `SOC_NET_MODE=existing` and
point `SOC_BRIDGE` / `SOC_GATEWAY` at it — no host network changes are made.

```bash
# Fully isolated 10.0.0.0/24 lab on its own bridge (this is the default):
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ssan9876/easy-deploy-SOC/main/soc-deploy.sh)"

# Or set it up on its own from a clone:
./scripts/setup-network.sh
```

## Requirements

- **Proxmox VE 7.x or 8.x**, run the command as `root` on the host shell.
- Enough free resources for the full lab: **~10 vCPU, ~20 GB RAM, ~230 GB disk**
  (the Kali desktop box is sized at 2 vCPU / 4 GB / 60 GB). Deploy components
  individually if that's tight.
- Outbound internet from the Proxmox host (to fetch ISOs, cloud images, agents,
  and — via NAT — for the lab VMs to provision themselves).
- `ifupdown2` (standard on Proxmox) so the isolated bridge can be applied without
  a reboot. Only needed in the default isolated mode.
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

You can **set your own passwords in the setup stage**: the menu's **Configure**
screen prompts for the Windows Administrator / lab-admin password and the lab
user (AD user / Kali analyst) password, each entered twice. Prefer env vars? Set
`SOC_ADMIN_PASSWORD` / `SOC_USER_PASSWORD`. Leave either blank and a strong one
is generated for you.

Whatever you pick (or the generated values) are saved to
**`/var/lib/easy-deploy-soc/lab.env`** on the Proxmox host (mode `0600`). The
Wazuh dashboard admin password is written on the SIEM VM at
`/root/WAZUH-CREDENTIALS.txt` once its install finishes.

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

- [docs/LEARNING.md](docs/LEARNING.md) — **start here to learn**: a phased
  SOC/blue-team roadmap (attack → observe → detect) built around this exact lab.
- [labs/](labs/) — **hands-on exercises**: run real attacks (enumeration,
  password spray, Kerberoasting, AS-REP, lateral movement) from the analyst box,
  each paired with the events it generates and a Wazuh detection to build.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — how the automation works end to end.
- [docs/USAGE.md](docs/USAGE.md) — walkthrough, practice scenarios, timings.
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — when something doesn't come up.

## Safety & licensing notes

- **The lab is isolated by default** (its own `vmbr9` / `10.0.0.0/24` with NAT).
  It intentionally contains weak configurations (an over-privileged account,
  static creds) for practice, so keep it that way — if you switch to
  `SOC_NET_MODE=existing`, put it on a dedicated bridge/VLAN and firewall it off.
- Windows runs on **Evaluation** licenses; they expire. Rebuild when they do.
- For authorized, educational security practice only.

## License

MIT — see [LICENSE](LICENSE).
