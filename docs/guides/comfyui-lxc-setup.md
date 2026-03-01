# ComfyUI LXC Setup: Host NVIDIA Driver + Docker

This guide documents setting up ComfyUI in a privileged Proxmox LXC container
with the host NVIDIA driver passed through via device bind-mounts.

## Why LXC, not KVM VM

VFIO GPU passthrough (KVM VM) was evaluated and abandoned for this hardware:

- **Platform**: Intel X299 (Skylake-X, gpu-workstation ASRock X299 Taichi)
- **GPU**: NVIDIA RTX 3060 (Ampere, PCIe `65:00.0`)
- **Issue**: Ampere GPUs + X299 PCIe bus lack FLR (Function Level Reset) on the audio
  function (`65:00.1`), which falls back to bus reset, crashing the host on X299

The LXC approach avoids VFIO entirely: the host NVIDIA driver owns the GPU, and the
LXC container accesses it via bind-mounted device nodes (`/dev/nvidia*`).

## Hardware and Prerequisites

| Item | Value |
|---|---|
| Proxmox node | gpu-workstation (10.0.0.15) |
| Motherboard | ASRock X299 Taichi (BIOS P2.50+) |
| CPU | Intel i7-7820X (Skylake-X, 8c/16t) |
| RAM | 48 GiB |
| RTX 3060 PCI | `0000:65:00.0` (passthrough GPU) |
| GTX 1080 Ti PCI | `0000:17:00.0` (host display, unused) |

**Before proceeding:**
- BIOS must be P2.50 or later (P1.70 launch BIOS has PCIe/stability issues)
- IOMMU enabled in BIOS (VT-d)
- Proxmox PVE kernel 6.x installed (6.17+ tested)

## 1) GRUB Configuration

Enable IOMMU and disable `sysfb` framebuffer init (prevents conflict with NVIDIA DRM):

```bash
# /etc/default/grub
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt initcall_blacklist=sysfb_init"
```

Apply and reboot:

```bash
update-grub && reboot
```

## 2) Clear VFIO Configuration (if previously set up)

If the node was previously configured for VFIO passthrough, remove GPU IDs from vfio.conf
so the NVIDIA driver can claim them:

```bash
# Comment out or empty /etc/modprobe.d/vfio.conf
# vfio-pci should not be bound to the GPU anymore
```

Remove vendor-reset if installed (AMD-only module, causes spontaneous crashes on NVIDIA):

```bash
dkms status | grep vendor-reset
dkms remove vendor-reset/0.1.1 --all
```

## 3) Install NVIDIA Driver (580.x .run installer)

Debian-packaged NVIDIA drivers (550.x) fail to build on PVE kernel 6.17+:
- Closed module: `drm_framebuffer_funcs` API changed in kernel 6.12+
- Open module: `dma_buf_attachment_is_dynamic` removed in kernel 6.13+

Use the official NVIDIA `.run` installer at version **580.x** or later:

```bash
# Download from https://www.nvidia.com/en-us/drivers/
# File: NVIDIA-Linux-x86_64-580.126.18.run (or later)
chmod +x NVIDIA-Linux-x86_64-580.126.18.run

# Purge any existing Debian NVIDIA packages first
apt-get remove -y --purge $(dpkg -l | grep -i nvidia | awk '{print $2}' | tr '\n' ' ') 2>/dev/null || true

# Install (no-opengl, no GUI components — headless PVE host)
./NVIDIA-Linux-x86_64-580.126.18.run --no-opengl-files --dkms --silent
```

Verify:

```bash
nvidia-smi  # should show both GPUs (1080 Ti + RTX 3060)
```

## 4) Configure NVIDIA Modules to Load at Boot

```bash
cat > /etc/modules-load.d/nvidia.conf << 'EOF'
nvidia
nvidia-uvm
nvidia-modeset
EOF
```

## 5) Create nvidia-device-nodes systemd Service

The `nvidia-uvm` kernel module registers `/dev/nvidia-uvm` **lazily** — device nodes
only appear after first userspace access. This service ensures all device nodes exist
before the LXC container starts:

```bash
cat > /etc/systemd/system/nvidia-device-nodes.service << 'EOF'
[Unit]
Description=Initialize NVIDIA device nodes (/dev/nvidia-uvm)
# Must run before any LXC container that uses NVIDIA devices
Before=pve-container@530.service
After=systemd-udev-settle.service

[Service]
Type=oneshot
# nvidia-smi access triggers nvidia-uvm device node creation
ExecStart=/usr/bin/nvidia-smi -L
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable nvidia-device-nodes.service
```

Verify device nodes exist after running the service:

```bash
systemctl start nvidia-device-nodes.service
ls /dev/nvidia*
# Expected: /dev/nvidia0  /dev/nvidia1  /dev/nvidiactl  /dev/nvidia-uvm  /dev/nvidia-uvm-tools
```

## 6) Create LXC Container via Terraform

The `module "comfyui_lxc"` in `infrastructure/main.tf` creates LXC 530 and writes
the NVIDIA passthrough config to `/etc/pve/lxc/530.conf` via SSH.

Verify the Ubuntu LXC template is available:

```bash
pveam list local
# Must show: local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst
# If missing: pveam update && pveam download local ubuntu-24.04-standard_24.04-2_amd64.tar.zst
```

Apply:

```bash
source .env.d/terraform.env
terraform -chdir=infrastructure plan
terraform -chdir=infrastructure apply
```

Start the container:

```bash
pct start 530
pct status 530  # → running
```

Verify NVIDIA devices inside the LXC:

```bash
pct exec 530 -- ls /dev/nvidia*
# Expected: /dev/nvidia0  /dev/nvidia1  /dev/nvidiactl  /dev/nvidia-uvm  /dev/nvidia-uvm-tools
```

## 7) Install Docker + nvidia-container-toolkit in LXC

SSH into the LXC container:

```bash
ssh root@10.0.0.53
```

Install Docker:

```bash
# Remove conflicting packages
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  apt-get remove -y $pkg 2>/dev/null || true
done

# Guard: skip if already installed
if ! command -v docker &>/dev/null; then
  apt-get update
  apt-get install -y ca-certificates curl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
    https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# Remove apparmor — Docker in LXC fails with apparmor installed (even if disabled)
apt-get remove -y apparmor 2>/dev/null || true
```

Install nvidia-container-toolkit:

```bash
if ! command -v nvidia-ctk &>/dev/null; then
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
    gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
  apt-get update
  apt-get install -y nvidia-container-toolkit
fi

nvidia-ctk runtime configure --runtime=docker
systemctl restart docker
```

Verify GPU access from Docker:

```bash
docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi
```

Expected: RTX 3060 GPU visible in the container output.

## 8) Deploy ComfyUI via Docker Compose

```bash
mkdir -p /opt/comfyui
cat > /opt/comfyui/docker-compose.yml << 'EOF'
services:
  comfyui:
    image: yanwk/comfyui-boot:latest
    container_name: comfyui
    restart: unless-stopped
    runtime: nvidia
    environment:
      - NVIDIA_VISIBLE_DEVICES=1   # RTX 3060 is nvidia1 (nvidia0 = GTX 1080 Ti)
      - NVIDIA_DRIVER_CAPABILITIES=compute,utility
    ports:
      - "8188:8188"
    volumes:
      - comfyui-data:/home/runner
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: ["1"]
              capabilities: [gpu]

volumes:
  comfyui-data:
EOF

cd /opt/comfyui && docker compose up -d
docker compose logs -f  # wait for first-run model downloads
```

Access ComfyUI at `http://10.0.0.53:8188`.

## 9) Update Terraform (set started = true)

Once the container is stable with ComfyUI running, update `main.tf` to have Terraform
manage the started state:

```hcl
module "comfyui_lxc" {
  # ...
  on_boot = true   # start on host reboot
  started = true   # terraform apply starts/keeps it running
}
```

## Troubleshooting

**`/dev/nvidia*` not in LXC on start:**
- Ensure `nvidia-device-nodes.service` is enabled and ran before LXC start
- Check: `systemctl status nvidia-device-nodes.service`
- Manual fix: `nvidia-smi -L && pct stop 530 && pct start 530`

**`docker run --gpus all` fails with "no NVIDIA devices":**
- Verify devices visible: `ls /dev/nvidia*` inside LXC
- Check: `nvidia-ctk runtime configure --runtime=docker && systemctl restart docker`
- Check: `docker info | grep -i runtime`

**Host crashes during LXC GPU workload:**
- Check `lsmod | grep vendor_reset` — should be empty (AMD-only, must not be loaded)
- Check dmesg for MCE errors: `dmesg | grep -i mce`
- Ensure BIOS is P2.50+ (launch BIOS P1.70 had PCIe stability issues)
