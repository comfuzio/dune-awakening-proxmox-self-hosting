

# 🏜️ Dune: Awakening — Native Proxmox Migration Guide

This guide explains how to deploy the **Dune: Awakening Self-Hosted Server** directly on **Proxmox VE (KVM)**.

While I will maintain this project due to the love in Dune: Awakening, myself am using another method for the time being for my own personal host (E-Arena.gr).
Also please have a look into another project of mine > In case your server isn't accessible from the web or you have dynamic IP and it has changed, you can fix this with this other script of mine > https://github.com/comfuzio/Dune-Awakening-remote-players-fix (backups always first)

# Warning! 
Official PTC Dune: Awakening discord community is highly toxic and hostile.

# You can deploy the server using **two different methods**:

| Method | Description |
|---|---|
| 📦 SteamCMD Method (Recommended) | Download the official VHDX directly on the Proxmox host |
| 🖥️ Hyper-V Migration Method | Import an already initialized VHDX from Windows/Hyper-V |

Running the server directly on Proxmox significantly reduces overhead and improves overall stability and performance compared to nested Hyper-V virtualization.

> 🚧 This project is still a work in progress.

---

# 💬 Community Discord

Join the E-Arena.gr community Discord: https://discord.gg/xmYSSTJkMz if you need support or help. Other channels or servers are no longer supported.

---

# 🚀 Benefits

| Feature | Description |
|---|---|
| 💾 Resource Efficiency | Save approximately **6GB RAM** by eliminating Windows Server overhead |
| 🐧 Native Linux Execution | Run the Kubernetes (**k3s**) cluster directly on Linux |
| ⚡ Better Performance | Improved virtualization performance using `--cpu host` |
| 🛠️ Cleaner Infrastructure | Simpler maintenance compared to nested Hyper-V setups |
| 📦 Multiple Deployment Options | Deploy using SteamCMD or Hyper-V export |

---

# 📋 Prerequisites

Before starting, ensure you have:

- 🎮 Access to the **Dune: Awakening Dedicated Server**
- 🖥️ A **Proxmox VE** node running:
  - **Proxmox VE 9.x recommended** (or latest fully updated stable branch)
  - Older versions may behave differently during VHDX import, EFI boot setup, or disk attachment
- 💾 System resources for the VM:
  - At least **40GB free RAM for the full experience**
  - Minimum **110GB free storage**
  - AVX2 CPU instruction set
- 🌐 Internet connectivity on the Proxmox host
- 📚 Official Funcom documentation for:
  - Account linking - https://account.duneawakening.com/
  - Token generation
  - Server authentication
  - Port Forwarding

---

# 🛠️ Deployment Methods

Choose **ONE** of the following methods.

---

# 📦 Method 1 — SteamCMD Download (Recommended)

This method downloads the official server image directly on the Proxmox host.

## 1️⃣ Install SteamCMD on Proxmox

Enable i386 support:

```bash
dpkg --add-architecture i386
```

Enable Debian non-free repositories:

```bash
sed -i 's/Components: main contrib non-free-firmware/Components: main contrib non-free non-free-firmware/g' /etc/apt/sources.list.d/debian.sources
```

Install SteamCMD:

```bash
apt update
apt install -y steamcmd
```

---

## 2️⃣ Download the Official Dune Server Image

Create a temporary directory:

```bash
mkdir -p /tmp/dune-download
```

Download the dedicated server package:

```bash
/usr/games/steamcmd \
  +@sSteamCmdForcePlatformType windows \
  +force_install_dir /tmp/dune-download \
  +login anonymous \
  +app_update 4754530 validate \
  +quit
```

VHDX location:

```text
/tmp/dune-download/Virtual Hard Disks/dune-server.vhdx
```

---

# 🖥️ Method 2 — Hyper-V Migration

This method migrates an already initialized VHDX.

Useful if:

- You already have a working Hyper-V deployment
- You want to preserve configuration/data
- SteamCMD download is unavailable

## 1️⃣ Obtain the VHDX

Run the dedicated server once inside Hyper-V.

Locate:

```text
dune-server.vhdx
```

---

## 2️⃣ Transfer the VHDX to Proxmox

Copy to the Proxmox host using SCP, rsync, SMB, WinSCP, or external storage.

Suggested path:

```text
/root/dune-server.vhdx
```

---

# 🖥️ Shared Proxmox VM Setup

These steps apply to **both methods**.

---

# 1️⃣ Create the Proxmox VM

Replace:

- `7000` → your VM ID
- `local-zfs` → your Proxmox storage
- `cores 12` → your CPU cores you want to assign to the vm

Create the VM:

```bash
qm create 7000 \
  --name dune-awakening \
  --memory 40960 \
  --cores 12 \
  --cpu host \
  --net0 virtio,bridge=vmbr0 \
  --ostype l26 \
  --machine q35 \
  --bios ovmf
```

---

# 2️⃣ Import the VHDX Disk

### SteamCMD Method

```bash
qm importdisk 7000 \
  "/tmp/dune-download/Virtual Hard Disks/dune-server.vhdx" \
  local-zfs
```

### Hyper-V Method

```bash
qm importdisk 7000 \
  "/root/dune-server.vhdx" \
  local-zfs
```

After import, Proxmox typically adds the disk as **Unused Disk 0**.

---

# 3️⃣ Attach the Imported Disk as SCSI 0 (Critical)

> ⚠️ Required step.  
> Funcom’s internal `setup.sh` expects the primary boot disk to be attached as **SCSI 0**.  
> If this is skipped or attached differently, automatic filesystem expansion may fail and the VM may remain at the original tiny disk size.

## Proxmox GUI (Recommended)

1. Open the VM in Proxmox
2. Go to **Hardware**
3. Double-click **Unused Disk 0**
4. Set Bus/Device to:

```text
SCSI 0
```

5. Save

---

## Via CLI add the virtio-scsi-single controller

```bash
qm set 7000 \
  --scsihw virtio-scsi-single \
  --scsi0 local-zfs:vm-7000-disk-0
```

This attaches the imported disk as the primary boot disk.

Add EFI disk:

```bash
qm set 7000 --efidisk0 local-zfs:0,format=raw
```

---

# 4️⃣ Resize the Disk (Recommended)

Resize **before first boot**.

Recommended additional space:

- **+110GB**

Example:

```bash
qm resize 7000 scsi0 +110G
```

This enlarges the virtual disk so Funcom’s initialization can expand the Alpine filesystem during setup.

---

# 5️⃣ Configure Boot Order & Display

```bash
qm set 7000 --boot order=scsi0
qm set 7000 --vga virtio
```

---

# 6️⃣ Start the VM

```bash
qm start 7000
```

---

# 🌐 Network Configuration (Post-Migration)

Because virtual hardware changes during import/migration, Alpine networking may need adjustment.

---

# Access the VM Console

Open Proxmox console and log in:

```text
Username: root
Password: dune
```

---

# Identify Network Interface

Run:

```bash
ip a
```

Typical interfaces:

```text
ens18
enp1s0
eth0
```

---

# Configure Networking

## Option A — DHCP Reservation (Recommended)

Reserve a fixed IP in your DHCP server/router.

---

## Option B — Static IP

Edit:

```bash
vi /etc/network/interfaces
```

Example:

```bash
auto lo
iface lo inet loopback

auto ens18
iface ens18 inet static
    address 192.168.1.50
    netmask 255.255.255.0
    gateway 192.168.1.1
```

---

# Apply Network Changes

```bash
service networking restart
service k3s restart
```

---

# 🌍 Router NAT / Port Forwarding

Forward traffic to the VM IP.

| Port Range | Protocol | Purpose |
|---|---|---|
| `7777-7810` | UDP | Game Servers / Battlegroups |
| `31982` | TCP | RMQ Management |

---

# 🚀 Initializing the Battlegroup

Once the VM is reachable:

## 1️⃣ Update Scripts

Modify:

- `initial-setup.ps1`
- `battlegroup.ps1`

Set VM IP:

```powershell
$vmIP = "YOUR_VM_IP"
```

---

## 2️⃣ Run Initial Setup

```powershell
initial-setup.ps1
```

This script:

- Injects Public/Local IP into `settings.conf`
- Triggers internal setup
- Expands filesystem
- Downloads/updates game binaries

---

## 3️⃣ Start Battlegroup

```powershell
battlegroup.ps1
```

Choose:

```text
Option 2 (start)
```

Wait for Kubernetes pods to initialize.

---

# 🧹 Cleanup

## SteamCMD Method

```bash
rm -rf /tmp/dune-download
```
# 🧹 Clean Up APT Notices (Optional)

Because we enabled the `i386` architecture for SteamCMD, you may see a notice when running `apt update` stating that the Proxmox repository doesn't support `i386`. 

To clean up your `apt update` output, we can tell Proxmox's repository manager to only look for 64-bit packages. 

Modern Proxmox installations use the DEB822 format (`.sources` files). You can inject the `Architectures: amd64` rule automatically by running this command:

```bash
sed -i '/^URIs:.*proxmox\.com/a Architectures: amd64' /etc/apt/sources.list.d/proxmox.sources
```
(Note: If you have the enterprise or test repositories enabled, you may also need to run this against /etc/apt/sources.list.d/pve-enterprise.sources or pve-test.sources).

Run apt update again, and the notice will be completely gone!

## Hyper-V Method

```bash
rm /root/dune-server.vhdx
```

---

# ⚖️ Legal Disclaimer

- **Dune: Awakening** is a trademark of Legendary and Funcom.
- This repository does **not** distribute:
  - Game files
  - Virtual disks
  - Proprietary assets
- Users are responsible for complying with Funcom EULA and hosting policies.

---

# ✅ Final Notes

Your Dune: Awakening server should now run natively on Proxmox VE with significantly lower overhead than nested Hyper-V deployments.

The most important Proxmox-specific requirement is ensuring the imported disk is attached as **SCSI 0 before first boot**, otherwise Funcom’s expansion process may fail.

This guide will evolve as dedicated server tooling changes during public testing.

Decoration and alignment of elements in this guide was done with the help of AI.

Happy hosting. 🏜️
