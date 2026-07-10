# Architecture

How easy-deploy-SOC turns one command into a working SOC lab.

## Entry point

`soc-deploy.sh` is the curl-able entry script. When run via
`bash -c "$(curl ...)"` it has no files next to it, so it **bootstraps**: it
downloads a tarball of this repository to a temp directory and points
`SOC_ASSET_DIR` at it. Run from a clone, it uses the repo in place. Either way it
then sources the libraries and per-component deploy scripts and shows a whiptail
menu.

## Layout

```
soc-deploy.sh              # menu + bootstrap (the 1-liner target)
scripts/
  lib/
    core.sh                # logging, whiptail wrappers, secrets, templating
    config.sh              # every default (env-overridable)
    proxmox.sh             # VMIDs, storage, ISO/image fetch, snippet helpers
    windows.sh             # build_windows_vm()
    linux.sh               # build_linux_vm(), cloud-init snippet install
  deploy-dc.sh             # Windows Server DC
  deploy-client.sh         # Windows 11 client
  deploy-linux.sh          # Kali analyst box (XFCE desktop)
  deploy-siem.sh           # Wazuh SIEM
  destroy-lab.sh           # teardown
autounattend/              # Windows answer files + first-logon PowerShell
  dc/       client/        install-agents.ps1
cloudinit/                 # cloud-init user-data templates
```

## Configuration & state

`config.sh` sets every value with `: "${VAR:=default}"`, so an environment
variable of the same name always wins. Generated passwords and discovered VMIDs
are persisted to `/var/lib/easy-deploy-soc/lab.env` (mode `0600`) by
`init_lab_secrets`, so separately-run components share one set of credentials and
the teardown script knows what to remove.

Templates use `@@PLACEHOLDER@@` markers. `render_template` copies a template and
`sed`-substitutes `name=value` pairs. Values destined for XML are passed through
`xml_escape` first (so a password containing `&`, `<`, `>` can't corrupt the
answer file); values destined for PowerShell/YAML are inserted raw.

## Windows unattended install

Reliability is favored over raw performance:

1. **SATA system disk + e1000 NIC.** Both have in-box Windows drivers, so Setup
   needs no injected VirtIO storage/network driver to start — the most common
   cause of stuck unattended installs. VirtIO performance can be adopted later
   from the attached VirtIO ISO.
2. **UEFI (OVMF) + TPM 2.0.** Required for Windows 11; the client answer file
   also sets the `LabConfig` bypass keys so Win11 installs on a plain VM.
3. **Answer ISO.** `deploy-*.sh` renders `autounattend.xml` (at the ISO root) plus
   the first-logon PowerShell (under `provision/`) into a temp tree and builds a
   tiny ISO with `genisoimage`. Windows Setup auto-detects `autounattend.xml` on
   any attached media. Three CD-ROMs are attached: Windows install, VirtIO tools,
   and this answer ISO.
4. **Boot order `ide0;sata0`.** The install ISO boots first; once Windows lays
   down its own UEFI boot entry it takes precedence on later reboots.

### First-logon flow

- **DC** (`setup-dc.ps1`): installs VirtIO guest tools, sets the static IP,
  installs the AD DS + DNS roles, and `Install-ADDSForest` promotes the box to
  the first DC of a new forest (auto-reboots). A `RunOnce` entry then runs
  `dc-stage2.ps1` after the reboot to create lab OUs/users and install Sysmon +
  the Wazuh agent.
- **Client** (`join-domain.ps1`): sets a static IP with the **DC as DNS**, waits
  for the DC to answer for the domain, `Add-Computer` joins it, and registers a
  `RunOnce` to install Sysmon + the Wazuh agent after the post-join reboot.

## Linux via cloud-init

`build_linux_vm` imports the cloud image straight onto `scsi0` (`import-from`),
attaches a cloud-init drive, and sets networking with `qm set
--ipconfig0/--nameserver`. The per-VM user-data is rendered from a template into
a **Snippets** storage and attached with `--cicustom user=`. Because custom
user-data replaces Proxmox's generated user block, the login user + hashed
password live inside the YAML (`openssl passwd -6`). The **SIEM** uses an Ubuntu
cloud image; the **analyst box** uses a **Kali** genericcloud image (a `.tar.xz`
archive `fetch_cloud_image` extracts to its raw disk before import).

- **Analyst box** runs Kali with an XFCE desktop (LightDM auto-login + xrdp) and
  the full Kali toolset by default (`SOC_LINUX_DESKTOP=0` for headless). It uses
  the DC for DNS (so it can resolve/enumerate the domain) and ships a Wazuh agent.
- **SIEM** uses the gateway for DNS and runs Wazuh's official all-in-one
  installer on first boot.

## Networking

Two modes, chosen by `SOC_NET_MODE`:

- **`isolated` (default).** `scripts/lib/network.sh` creates a dedicated bridge
  (`SOC_LAB_BRIDGE`, default `vmbr9`) with no physical ports, gives the Proxmox
  host the gateway address `SOC_GATEWAY` (`10.0.0.1`) on it, and — when
  `SOC_NET_NAT=1` — enables IP forwarding plus an iptables `MASQUERADE` rule out
  the host's WAN interface (auto-detected from the default route). The lab can
  reach the internet for provisioning but is walled off from the host's LAN. The
  bridge stanza (including the NAT `post-up`/`post-down` rules so they persist
  across reboots) is written to `/etc/network/interfaces` inside
  `# BEGIN/END easy-deploy-SOC` markers and applied with `ifreload -a`. Creation
  is idempotent — it only ever rewrites its own marked block — and it refuses to
  touch a bridge name that already exists and isn't ours. Teardown removes the
  block and deletes the bridge. When `SOC_PUBLISH_SIEM=1` (default) the same
  block also adds a `DNAT` port-forward (`SOC_SIEM_PUBLISH_PORT`, default `8443`)
  from the host to the SIEM's `:443`, so the Wazuh dashboard is reachable from a
  machine off the lab subnet at `https://<proxmox-host-ip>:8443`.
- **`existing`.** VMs attach to a bridge you already run (`SOC_BRIDGE`, default
  `vmbr0`) using a gateway/router you already have (`SOC_GATEWAY`). No host
  network configuration is changed.

Addressing is static in a `/24` (`SOC_SUBNET`, default `10.0.0`), optionally
VLAN-tagged via `SOC_VLAN`. DNS is arranged so every box can resolve both the
domain and the internet even though the gateway itself isn't a resolver: the DC
(`10.0.0.10`) serves `soclab.local` and forwards external lookups to
`SOC_UPSTREAM_DNS` (default `1.1.1.1`); the Windows client and the analyst box
use the DC for DNS (the analyst also lists the upstream resolver as a fallback so
its package installs work before the DC's DNS is ready); the SIEM, not being a
domain member, resolves directly via the upstream resolver.
