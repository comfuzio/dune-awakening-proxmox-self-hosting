# 🏜️ Dune: Awakening — Native Proxmox Migration Guide

This guide explains how to deploy the **Dune: Awakening Self-Hosted Server** directly on **Proxmox VE (KVM)** without requiring a permanent Windows/Hyper-V environment.

The server image is downloaded directly from Steam using SteamCMD and then imported into Proxmox as a native VM.

Running the server directly on Proxmox significantly reduces overhead and improves overall stability and performance.

> 🚧 This project is still work in progress.

## 💬 Community Discord

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
| 📦 Direct Steam Download | No need to manually extract VHDX files from Hyper-V |

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

# 🛠️ Installation Steps

---

# 1️⃣ Install SteamCMD on Proxmox

Run the following directly on the Proxmox host shell.

## Enable 32-bit Architecture Support

SteamCMD requires i386 compatibility libraries.

```bash
dpkg --add-architecture i386
```

---

## Enable Debian Non-Free Repositories

```bash
sed -i 's/Components: main contrib non-free-firmware/Components: main contrib non-free non-free-firmware/g' /etc/apt/sources.list.d/debian.sources
```

---

## Install SteamCMD

```bash
apt update
apt install -y steamcmd
```

---

# 2️⃣ Download the Official Dune Server Image

Create a temporary download directory:

```bash
mkdir -p /tmp/dune-download
```

Download the official dedicated server package directly from Steam:

```bash
/usr/games/steamcmd \
  +@sSteamCmdForcePlatformType windows \
  +force_install_dir /tmp/dune-download \
  +login anonymous \
  +app_update 4754530 validate \
  +quit
```

The VHDX image will be downloaded to:

```text
/tmp/dune-download/Virtual Hard Disks/dune-server.vhdx
```

---

# 3️⃣ Create the Proxmox VM

> ⚠️ Replace:
>
> - `7000` with your desired VM ID
> - `local-zfs` with your actual Proxmox storage pool

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

# 4️⃣ Import the VHDX Disk

```bash
qm importdisk 7000 \
  "/tmp/dune-download/Virtual Hard Disks/dune-server.vhdx" \
  local-zfs
```

---

# 5️⃣ Attach the Imported Disk

```bash
qm set 7000 \
  --scsihw virtio-scsi-single \
  --scsi0 local-zfs:vm-7000-disk-0
```

---

# 6️⃣ Resize the Disk (Recommended)

The default image is extremely small and should be expanded before first boot.

Recommended minimum additional storage:

- **+110GB**

Example:

```bash
qm resize 7000 scsi0 +110G
```

---

# 7️⃣ Configure Boot Order & Display

```bash
qm set 7000 --boot order=scsi0
qm set 7000 --vga virtio
```

---

# 8️⃣ Start the VM

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

4. Run:

```powershell
battlegroup.ps1
```

5. Select:

```text
Option 2 (start)
```

Wait for the Kubernetes pods to initialize.

---

# 🧹 Cleanup

After confirming successful operation:

```bash
rm -rf /tmp/dune-download
```

This reclaims storage space on the Proxmox host.

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

This guide is still evolving as the dedicated server tooling changes during the public testing phases.

Parts of this guide were assisted by AI tooling for:
- Formatting
- Documentation cleanup
- Markdown restructuring

Happy hosting. 🏜️
