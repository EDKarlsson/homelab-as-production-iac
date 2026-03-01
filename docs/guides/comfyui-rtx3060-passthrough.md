# ComfyUI VM with NVIDIA RTX 3060 Passthrough

This guide shows how to pass an NVIDIA RTX 3060 from Proxmox into the ComfyUI VM and make it available to Docker for AI/ML workloads.

## Scope

- Host: Proxmox VE node running the ComfyUI VM
- Guest: Ubuntu 24.04 VM managed by `infrastructure/modules/comfyui`
- Runtime: Docker Compose (`comfyui` service)

## 1) Prepare the Proxmox host

1. Enable IOMMU in BIOS/UEFI.
1. Enable IOMMU in kernel args:
   - Intel CPUs: `intel_iommu=on iommu=pt`
   - AMD CPUs: `amd_iommu=on iommu=pt`
1. Update bootloader and reboot:

```bash
sudo update-grub
sudo reboot
```

1. After reboot, verify IOMMU is active:

```bash
dmesg | grep -Ei "IOMMU|DMAR"
```

## 2) Identify GPU PCI devices

Find the RTX 3060 GPU function and audio function on the target node:

```bash
lspci -nn | grep -Ei "NVIDIA|VGA|3D|Audio"
```

Record both PCI addresses, for example:
- GPU: `0000:01:00.0`
- HDMI audio: `0000:01:00.1`

## 3) Bind the GPU to VFIO on Proxmox

1. Load VFIO modules:

```bash
cat <<'MODS' | sudo tee /etc/modules-load.d/vfio.conf
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
MODS
```

1. Blacklist host NVIDIA drivers (host should not claim passthrough GPU):

```bash
cat <<'EOF2' | sudo tee /etc/modprobe.d/blacklist-nvidia-passthrough.conf
blacklist nouveau
blacklist nvidia
blacklist nvidiafb
EOF2
```

1. Rebuild initramfs and reboot:

```bash
sudo update-initramfs -u
sudo reboot
```

1. Confirm VFIO driver binding:

```bash
lspci -nnk -s 01:00.0
lspci -nnk -s 01:00.1
```

Expected: `Kernel driver in use: vfio-pci`.

## 4) Enable passthrough in Terraform module

In `infrastructure/main.tf`, set these module arguments:

```hcl
module "comfyui" {
  source         = "./modules/comfyui"
  ssh_public_key = data.onepassword_item.k3s_cluster.public_key

  gpu_passthrough_enabled = true
  gpu_pci_id              = "0000:01:00.0"
  gpu_audio_pci_id        = "0000:01:00.1"

  # Defaults are already compatible for PCIe passthrough:
  # machine_type = "q35"
  # bios_type    = "ovmf"
}
```

Then apply:

```bash
terraform -chdir=infrastructure plan
terraform -chdir=infrastructure apply
```

## 5) Verify GPU in guest + Docker

SSH to the ComfyUI VM and validate:

```bash
lspci | grep -i nvidia
nvidia-smi
sudo docker exec comfyui nvidia-smi
```

If `nvidia-smi` fails on first boot, reboot once after cloud-init finishes:

```bash
sudo reboot
sudo systemctl restart comfyui
```

## 6) Verify ComfyUI uses CUDA

- Open `http://<comfyui-ip>:8188`
- Run a small workflow
- Confirm logs show CUDA device availability:

```bash
sudo docker logs comfyui | grep -Ei "cuda|nvidia|torch"
```

## Troubleshooting

- If passthrough fails at boot, verify IOMMU and VFIO binding again on host.
- If guest sees GPU but container does not, run `sudo nvidia-ctk runtime configure --runtime=docker` and restart Docker.
- If VM fails to start with passthrough, check the GPU IOMMU group and whether another host process still uses the device.
