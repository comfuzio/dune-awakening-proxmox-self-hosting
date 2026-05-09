# Dune: Awakening - Native Proxmox Migration Guide

This guide provides a step-by-step walkthrough for migrating the **Dune: Awakening Self-Hosted Server** from a Windows/Hyper-V environment to a native **Proxmox (KVM)** Virtual Machine.

## 🚀 Benefits
- **Resource Efficiency:** Saves ~6GB RAM by removing Windows Server overhead.
- **Stability:** Native Linux execution for the Kubernetes (k3s) cluster.
- **Performance:** Direct hardware access via the `host` CPU type[cite: 1].

## 📋 Prerequisites
1. Access to the **Dune: Awakening Public Test Client Server** on Steam (AppID: 3104830)[cite: 1].
2. A Proxmox VE node with at least 42GB of free RAM.
3. The `dune-server.vhdx` file (found in the Steam installation directory)[cite: 1].
4. Please also follow the guidline of funcome https://duneawakening.com/self-hosted-servers/

## 🛠️ Installation Steps

### 1. Transfer the Virtual Disk
Bring your `dune-server.vhdx` into your Proxmox `/root` directory using WinSCP, rsync, or a direct download.

### 2. Create the VM
Run the following commands in the Proxmox Shell (Replace `7000` with your desired VM ID):

```bash
# Create the VM Shell
qm create 7000 --name dune-awakening --memory 40960 --cores 12 --cpu host --net0 virtio,bridge=vmbr0 --ostype l26 --machine q35 --bios ovmf

# Add EFI Disk (Required for UEFI Boot)
qm set 7000 --efidisk0 local-zfs:0,format=raw

# Import the VHDX into your ZFS/LVM storage
qm importdisk 7000 dune-server.vhdx local-zfs

# Attach the imported disk and set boot order
qm set 7000 --scsihw virtio-scsi-pci --scsi0 local-zfs:vm-7000-disk-0
qm set 7000 --boot order=scsi0
qm set 7000 --vga virtio
