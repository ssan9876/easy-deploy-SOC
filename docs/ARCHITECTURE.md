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
  deploy-linux.sh          # Ubuntu analyst box
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

`build_linux_vm` imports the Ubuntu cloud image straight onto `scsi0`
(`import-from`), attaches a cloud-init drive, and sets networking with `qm set
--ipconfig0/--nameserver`. The per-VM user-data is rendered from a template into
a **Snippets** storage and attached with `--cicustom user=`. Because custom
user-data replaces Proxmox's generated user block, the login user + hashed
password live inside the YAML (`openssl passwd -6`).

- **Analyst box** uses the DC for DNS (so it can resolve/enumerate the domain)
  and installs offensive/defensive tooling + a Wazuh agent.
- **SIEM** uses the gateway for DNS and runs Wazuh's official all-in-one
  installer on first boot.

## Networking

All VMs attach to `SOC_BRIDGE` (default `vmbr0`), optionally VLAN-tagged via
`SOC_VLAN`. Addressing is static in a `/24` (`SOC_SUBNET`), with the DC at `.10`
serving DNS for the domain members. Point `SOC_GATEWAY` at whatever provides the
lab's route to the internet (your router, a pfSense/OPNsense VM, etc.).
