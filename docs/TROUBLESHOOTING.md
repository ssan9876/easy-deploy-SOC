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

## "No storage advertises 'snippets' content"

Cloud-init needs a Snippets-enabled storage. Enable it under
*Datacenter → Storage → (storage) → Edit → Content → check **Snippets***, or
point `SOC_SNIPPET_STORAGE` at one that has it.

## Windows install seems stuck / loops on "Press any key to boot from CD"

- The unattended install can sit on black screens for minutes — give it time.
- If it genuinely loops back to the installer instead of booting the new install,
  open the VM console, detach the Windows ISO from `ide0` (*Hardware → CD/DVD →
  Edit → Do not use any media*), and reboot. Windows' own UEFI boot entry then
  takes over. This is rare with the default `ide0;sata0` boot order.

## Windows install can't find a disk

The default uses a **SATA** system disk specifically so no driver injection is
needed. If you changed the disk bus to VirtIO SCSI, Setup won't see the disk
unless you load the VirtIO driver from the attached `virtio-win` ISO during the
"Where do you want to install Windows?" step. Keep SATA for hands-off installs.

## Client never joins the domain

The client points DNS at the DC and waits up to ~15 minutes for it. Check:

- The **DC finished promoting** (it reboots twice; `soclab.local` must resolve).
  From the client console: `Resolve-DnsName soclab.local -Server 10.10.10.10`.
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
