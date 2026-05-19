# 🏜️ Dune: Awakening — Native Proxmox Migration Guide

This guide explains how to deploy the **Dune: Awakening Self-Hosted Server** directly on **Proxmox VE (KVM)**.

You can deploy the server using **two different methods**:

| Method | Description |
|---|---|
| 📦 SteamCMD Method (Recommended) | Download the official VHDX directly on the Proxmox host |
| 🖥️ Hyper-V Migration Method | Export an already initialized VHDX from Windows/Hyper-V |

Running the server directly on Proxmox significantly reduces overhead and improves overall stability and performance compared to nested Hyper-V virtualization.

> 🚧 This project is still work in progress.

---

# 💬 Community Discord

Join the community Discord:

https://discord.gg/rgR79rfnRZ

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

- 🎮 Access to the **Dune: Awakening Public Test Dedicated Server**
- 🖥️ A **Proxmox VE** node with:
  - At least **42GB free RAM**
  - Minimum **100GB free storage**
- 🌐 Internet connectivity on the Proxmox host
- 📚 Official Funcom documentation for:
  - Account linking
  - Token generation
  - Server authentication

---

# 🛠️ Deployment Methods

Choose **ONE** of the following methods.

---

# 📦 Method 1 — Direct SteamCMD Download (Recommended)

This method downloads the official dedicated server image directly on the Proxmox host.

---

## 1️⃣ Install SteamCMD on Proxmox

Run the following directly on the Proxmox host shell.

### Enable 32-bit Architecture Support

```bash
dpkg --add-architecture i386
```

---

### Enable Debian Non-Free Repositories

```bash
sed -i 's/Components: main contrib non-free-firmware/Components: main contrib non-free non-free-firmware/g' /etc/apt/sources.list.d/debian.sources
```

---

### Install SteamCMD

```bash
apt update
apt install -y steamcmd
```

---

## 2️⃣ Download the Official Dune Server Image

Create a temporary download directory:

```bash
mkdir -p /tmp/dune-download
```

Download the dedicated server package directly from Steam:

```bash
/usr/games/steamcmd \
  +@sSteamCmdForcePlatformType windows \
  +force_install_dir /tmp/dune-download \
  +login anonymous \
  +app_update 4754530 validate \
  +quit
```

The VHDX image will be located at:

```text
/tmp/dune-download/Virtual Hard Disks/dune-server.vhdx
```

---

# 🖥️ Method 2 — Hyper-V Migration

This method migrates an already initialized VHDX from Windows/Hyper-V.

Useful if:

- You already have a working Hyper-V deployment
- You want to preserve existing configuration/data
- SteamCMD download is unavailable

---

## 1️⃣ Obtain the VHDX File

Run the dedicated server at least once inside Hyper-V.

Locate the generated VHDX file:

```text
dune-server.vhdx
```

---

## 2️⃣ Transfer the VHDX to Proxmox

Copy the VHDX file to the Proxmox host using one of the following methods:

- WinSCP
- SCP
- rsync
- SMB share
- External drive

Suggested destination:

```text
/root/dune-server.vhdx
```

---

# 🖥️ Shared Proxmox VM Setup

The following steps apply to **both deployment methods**.

---

# 1️⃣ Create the Proxmox VM

> ⚠️ Replace:
>
> - `7000` with your desired VM ID
> - `local-zfs` with your actual Proxmox storage pool

---

## Create the VM

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

## Add EFI Disk

```bash
qm set 7000 --efidisk0 local-zfs:0,format=raw
```

---

# 2️⃣ Import the VHDX Disk

## SteamCMD Method

```bash
qm importdisk 7000 \
  "/tmp/dune-download/Virtual Hard Disks/dune-server.vhdx" \
  local-zfs
```

---

## Hyper-V Migration Method

```bash
qm importdisk 7000 \
  "/root/dune-server.vhdx" \
  local-zfs
```

---

# 3️⃣ Attach the Imported Disk

```bash
qm set 7000 \
  --scsihw virtio-scsi-single \
  --scsi0 local-zfs:vm-7000-disk-0
```

---

# 4️⃣ Resize the Disk (Recommended)

The default image is extremely small and should be expanded before first boot.

Recommended minimum additional storage:

- **+110GB**

Example:

```bash
qm resize 7000 scsi0 +110G
```

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

Because the virtual hardware changes during migration/import, the Alpine Linux network interface must be reconfigured.

---

# Access the VM Console

Open the VM console from Proxmox and log in using:

```text
Username: root
Password: dune
```

---

# Identify the Network Interface

Run:

```bash
ip a
```

Typical interface names include:

```text
ens18
enp1s0
eth0
```

---

# Configure Networking

## Option A — DHCP Reservation (Recommended)

Configure your router/DHCP server to always assign the same IP address to the VM MAC address.

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

To allow external players to connect, configure port forwarding to the VM IP address.

| Port Range | Protocol | Purpose |
|---|---|---|
| `7777-7810` | UDP | Game Servers / Battlegroups |
| `31982` | TCP | RMQ Management |

---

# 🚀 Initializing the Battlegroup

Once the VM is reachable:

1. Open your modified:
   - `initial-setup.ps1`
   - `battlegroup.ps1`

2. Set the VM IP:

```powershell
$vmIP = "YOUR_VM_IP"
```

3. Run:

```powershell
initial-setup.ps1
```

This script will:

- Inject Public/Local IP values into `settings.conf`
- Trigger the internal setup process
- Expand the filesystem
- Download/update game binaries

---

4. Run:

```powershell
battlegroup.ps1
```

Select:

```text
Option 2 (start)
```

Wait for the Kubernetes pods to initialize.

---

# 🧹 Cleanup

## SteamCMD Method

```bash
rm -rf /tmp/dune-download
```

---

## Hyper-V Migration Method

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
- Users are responsible for complying with the official Funcom EULA and hosting policies.

---

# ✅ Final Notes

Your Dune: Awakening server should now operate natively under Proxmox VE with significantly lower overhead compared to nested Windows/Hyper-V deployments.

This guide is still evolving as the dedicated server tooling changes during public testing phases.

Parts of this guide were assisted by AI tooling for:
- Formatting
- Documentation cleanup
- Markdown restructuring

Happy hosting. 🏜️
