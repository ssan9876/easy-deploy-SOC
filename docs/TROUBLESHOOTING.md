# Troubleshooting

## ISO download fails / link is dead

Microsoft's Evaluation Center links rotate often, so the built-in Windows URLs go
stale. When a download fails the script offers to pick an ISO already on your
Proxmox ISO storage.

1. Download the ISO from the Microsoft Evaluation Center:
   - *Windows Server 2022* (evaluation, 180 days)
   - *Windows 11 Enterprise* (evaluation, 90 days)
2. Upload it: *Proxmox → your storage → ISO Images → Upload*.
3. Either select it when prompted, or set the env vars to your file name:
   ```bash
   SOC_WINSRV_ISO_NAME=my-server2022.iso SOC_WIN11_ISO_NAME=my-win11.iso ./scripts/deploy-dc.sh
   ```

## Isolated lab network / no internet in the VMs

In the default `isolated` mode the deployer adds a `vmbr9` bridge (`10.0.0.1/24`)
to `/etc/network/interfaces` and NATs the lab out the host's WAN interface.

- **Nothing happens / bridge didn't apply.** Ensure `ifupdown2` is installed
  (standard on Proxmox); the script uses `ifreload -a`. Check the block was added
  between `# BEGIN easy-deploy-SOC` and `# END easy-deploy-SOC`.
- **VMs can't reach the internet.** The host needs a working default route (the
  NAT egress interface is taken from `ip route show default`). Confirm
  forwarding: `sysctl net.ipv4.ip_forward` should be `1`, and
  `iptables -t nat -L POSTROUTING` should show the `MASQUERADE` for
  `10.0.0.0/24`. If your host firewalls the `FORWARD` chain, allow the lab
  subnet.
- **"Bridge vmbrX already exists and wasn't created by us."** Pick a free bridge
  name with `SOC_LAB_BRIDGE=vmbr9` (or another unused number), or use
  `SOC_NET_MODE=existing` to attach to a bridge you already have.
- **Want it on a bridge you already run?** `SOC_NET_MODE=existing SOC_BRIDGE=vmbr0
  SOC_GATEWAY=<your-router>` — no host network changes are made.
- **Remove the lab bridge later:** the teardown (`./scripts/destroy-lab.sh` or
  menu → Destroy) offers to remove it, or run it directly:
  `source scripts/lib/{core,config,proxmox,network}.sh; destroy_lab_network`.

## Name resolution fails during provisioning

Every box is set up to resolve both the domain and the internet, but if a VM
came up before the DC's DNS was ready you can see transient failures. The analyst
box lists the upstream resolver (`SOC_UPSTREAM_DNS`, default `1.1.1.1`) as a
fallback; the SIEM uses it directly. If the DC never forwards external names,
confirm `Get-DnsServerForwarder` on the DC lists the upstream IP (added by
`dc-stage2.ps1`).

## "No storage advertises 'snippets' content"

Cloud-init needs a Snippets-enabled storage. Enable it under
*Datacenter → Storage → (storage) → Edit → Content → check **Snippets***, or
point `SOC_SNIPPET_STORAGE` at one that has it.

## Windows install never starts / "no bootable media"

Microsoft's UEFI install media shows a **"Press any key to boot from CD or
DVD..."** prompt on every boot from the CD. With nobody at the console the prompt
times out, the firmware gives up on the optical drive and falls through to the
still-empty system disk, and OVMF reports **no bootable media** — so the install
never begins. The deployer now taps a key past that prompt automatically for the
first ~2 minutes after the VM starts (`nudge_boot_from_cd` in
`scripts/lib/windows.sh`, via `qm sendkey`), so the install proceeds hands-off.

- If you start a Windows VM by hand (e.g. `qm start`), open its console within a
  few seconds and press a key yourself to get past the prompt.
- The auto-tap only runs during the first boot window; later reboots intentionally
  let the prompt time out so Windows' own UEFI boot entry on the disk takes over.

## Windows install seems stuck / loops on "Press any key to boot from CD"

- The unattended install can sit on black screens for minutes — give it time.
- If it genuinely loops back to the installer instead of booting the new install,
  open the VM console, detach the Windows ISO from `ide0` (*Hardware → CD/DVD →
  Edit → Do not use any media*), and reboot. Windows' own UEFI boot entry then
  takes over. This is rare with the default `ide0;sata0` boot order.

## Proxmox console (noVNC) is blank for the Linux / Wazuh VMs

The Ubuntu VMs are created with a standard VGA display (`--vga std`) so the
Proxmox **Console** (noVNC) shows a login prompt. If you customised the VM and set
`--vga serial0`, the graphical console goes blank because all output is redirected
to the serial port; switch it back to `std` under *Hardware → Display*, or use
`qm terminal <vmid>` to reach the serial console instead.

## Windows install can't find a disk / "no drive to install to"

Two things have to line up for Setup to accept the disk:

- **Disk bus.** The default uses a **SATA** system disk specifically so no driver
  injection is needed. If you changed the disk bus to VirtIO SCSI, Setup won't see
  the disk unless you load the VirtIO driver from the attached `virtio-win` ISO
  during the "Where do you want to install Windows?" step. Keep SATA for hands-off
  installs.
- **Partition style.** The VMs boot **UEFI (OVMF)**, so the answer file lays the
  disk out as **GPT** — an EFI System Partition (FAT32) + MSR + Windows (NTFS).
  An MBR-style layout (an `Active` NTFS "System" partition) is rejected on UEFI
  and makes Setup report no suitable install drive. If you edit
  `autounattend/*/autounattend.xml`, keep the GPT layout unless you also switch
  the VM to SeaBIOS.

## Client never joins the domain

The client points DNS at the DC and waits up to ~15 minutes for it. Check:

- The **DC finished promoting** (it reboots twice; `soclab.local` must resolve).
  From the client console: `Resolve-DnsName soclab.local -Server 10.0.0.10`.
- Both are on the **same bridge/VLAN** and subnet.
- Re-run the join manually on the client:
  `powershell -File C:\provision\join-domain.ps1`. Logs are in
  `C:\provision\*.log`.

## No agents showing up in Wazuh

- Wazuh's all-in-one install takes 10–15 minutes on first boot; the dashboard
  isn't up until it finishes. Watch `/var/log/wazuh-install.log` on the SIEM.
- Endpoints install their agent late in provisioning (after the Windows reboots).
  Check `C:\provision\install-agents.log` (Windows) or
  `/var/log/wazuh-agent-install.log` (Linux).
- Confirm the endpoint can reach the SIEM on TCP **1514/1515**.

## Where are the logs?

- **Proxmox host**: script output is on your terminal; state in
  `/var/lib/easy-deploy-soc/lab.env`.
- **Windows guests**: `C:\provision\*.log` (setup-dc, dc-stage2, join-domain,
  install-agents).
- **Linux guests**: `/var/log/cloud-init-output.log`, plus
  `/var/log/wazuh-install.log` (SIEM) / `/var/log/wazuh-agent-install.log`.

## Start over

`./scripts/destroy-lab.sh` (or the menu's Destroy) removes the VMs and generated
artifacts. Then re-run the deployer.
