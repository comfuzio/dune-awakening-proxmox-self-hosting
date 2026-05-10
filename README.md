# 🏜️ Dune: Awakening — Native Proxmox Migration Guide

This guide explains how to migrate the **Dune: Awakening Self-Hosted Server** from a **Windows/Hyper-V environment** to a **native Proxmox VE (KVM) virtual machine**.

Running the server directly on Proxmox significantly reduces overhead and improves overall stability and performance.

This is work in progress, please join the discord of the community: https://discord.gg/rgR79rfnRZ

---

# 🚀 Benefits

| Feature | Description |
|---|---|
| 💾 Resource Efficiency | Save approximately **6GB RAM** by eliminating Windows Server overhead |
| 🐧 Native Linux Execution | Run the Kubernetes (**k3s**) cluster directly on Linux |
| ⚡ Better Performance | Improved virtualization performance using `--cpu host` |
| 🛠️ Cleaner Infrastructure | Simpler maintenance compared to nested Hyper-V setups |

---

# 📋 Prerequisites

Before starting, ensure you have:

- 🎮 Access to the **Dune: Awakening Public Test Client Server**
  - Steam AppID: `3104830`
- 🖥️ A **Proxmox VE** node with:
  - At least **42GB free RAM**
  - Enough storage space for the imported VM disk(minimum 100gb)
- 📦 The `dune-server.vhdx` file from your Steam installation directory
- 📚 The official Funcom documentation for:
  - Account linking
  - Token generation
  - Server authentication

---

# 🛠️ Installation Steps

---

## 1️⃣ Transfer the Virtual Disk

Copy the `dune-server.vhdx` file to your Proxmox host.

Recommended methods:

- WinSCP
- `scp`
- `rsync`
- Direct download

Suggested destination:

```bash
/root/dune-server.vhdx
```

---

## 2️⃣ Create the Proxmox VM

Run the following commands directly on the Proxmox host shell.

> ⚠️ Replace:
>
> - `7000` with your desired VM ID
> - `local-zfs` with your actual Proxmox storage pool

### Create the VM

```bash
qm create 7000 --name dune-awakening --memory 40960 --cores 12 --cpu host --net0 virtio,bridge=vmbr0 --ostype l26 --machine q35 --bios ovmf
```

---

### Add EFI Disk (Required for UEFI Boot)

```bash
qm set 7000 --efidisk0 local-zfs:0,format=raw
```

---

### Import the VHDX Disk

```bash
qm importdisk 7000 /root/dune-server.vhdx local-zfs
```

---

### Attach the Imported Disk

```bash
qm set 7000 --scsihw virtio-scsi-pci --scsi0 local-zfs:vm-7000-disk-0
qm set 7000 --scsihw virtio-scsi-single --scsi0 local-zfs:vm-7000-disk-1,discard=on,cache=writeback,ssd=1,iothread=1
```

---

### Configure Boot Order & Display

```bash
qm set 7000 --boot order=scsi0
qm set 7000 --vga virtio
```

---

# 🌐 Network Configuration (Post-Migration)

Because the virtual hardware changes during migration, the network interface inside Alpine Linux must be reconfigured.

---

## Access the VM Console

Open the VM console from Proxmox and log in using:

```text
Username: root
Password: dune
```

---

## Identify the Network Interface

Run:

```bash
ip a
```

Typical interface names include:

```text
enp1s0
ens18
eth0
```

---

## Configure Networking

### Option A — DHCP Reservation (Recommended)

Configure your router/DHCP server to always assign the same IP address to the VM MAC address.

---

### Option B — Static IP

Edit:

```bash
/etc/network/interfaces
```

Example:

```bash
auto lo
iface lo inet loopback

auto enp1s0
iface enp1s0 inet static
    address 192.168.1.50
    netmask 255.255.255.0
    gateway 192.168.1.1
```

---

## Apply Network Changes

```bash
service networking restart
service k3s restart
```

---

# 🌍 Router NAT / Port Forwarding

To allow external players to connect, configure port forwarding on your router to the VM IP address.

| Port Range | Protocol | Purpose |
|---|---|---|
| `7777-7810` | UDP | Game Servers / Battlegroups |
| `31982` | TCP | RMQ Management |

---

# 🧹 Cleanup

After confirming the VM boots successfully:

```bash
rm /root/dune-server.vhdx
```

This reclaims storage space on the Proxmox host.

---

## 🚀 Initializing the Battlegroup
Once your VM is running in Proxmox and you can ping it, follow these steps from your Windows PC:

1. **Configure the IP:** Open my modified `initial-setup.ps1` and `battlegroup.ps1` from my "proxmox" folder and set the `$vmIP` variable to your Proxmox VM's IP.
2. **Run Setup:** Run `initial-setup.ps1` as Administrator. This will:
   - Inject your Public/Local IP into the VM's `settings.conf`.
   - Trigger the internal `setup` script to resize the disk and download game binaries[cite: 1].
3. **Launch:** Open `battlegroup.ps1`, select **Option 2 (start)**, and wait for the Kubernetes pods to initialize[cite: 1].

# ⚖️ Legal Disclaimer

- **Dune: Awakening** is a trademark of Legendary and Funcom.
- This repository does **not** distribute:
  - Game files
  - Virtual disks
  - Proprietary assets
- Users are responsible for complying with the official Funcom EULA and server hosting policies.

---

# ✅ Final Notes

Once networking and port forwarding are configured, your Dune: Awakening dedicated server should operate fully natively under Proxmox VE with lower overhead and improved stability compared to the original Windows/Hyper-V deployment.

Parts of this guide have been written by AI (gemini), mostly the visual parts and the details of the guide. Most of the work is based on template I am mostly working to import .vhdx .qcow2 and other formats to my proxmox hosts.

Happy hosting. 🏜️
