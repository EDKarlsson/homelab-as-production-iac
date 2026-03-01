---
title: Proxmox LXC Patterns
description: Patterns and technical reference for managing Proxmox LXC containers via Terraform including Docker-in-LXC, provisioning, and keepalived VRRP failover
published: true
date: 2026-02-18
tags:
  - proxmox
  - lxc
  - docker
  - terraform
  - keepalived
  - provisioning
---

Patterns and technical reference for managing Proxmox LXC containers via Terraform (bpg/proxmox provider), including Docker-in-LXC, provisioning without cloud-init, and keepalived VRRP failover.

## Docker-in-LXC

Running Docker inside an LXC container requires specific Proxmox container configuration. This is the pattern used for infrastructure services that must run outside the K3s cluster (e.g., 1Password Connect).

### Required Container Features

```hcl
resource "proxmox_virtual_environment_container" "example" {
  # Privileged container required for Docker-in-LXC
  unprivileged = false

  features {
    nesting = true   # Allows nested namespaces (required for Docker)
    keyctl  = true   # Allows key management syscalls (required for Docker)
  }
}
```

**Why each setting is needed:**

| Setting | Purpose |
|---------|---------|
| `unprivileged = false` | Docker needs access to host kernel features (cgroups, namespaces) that unprivileged containers cannot provide. Specifically, Docker's storage drivers (overlay2) and network management require root-level capabilities. |
| `nesting = true` | Docker creates its own namespaces (PID, network, mount) inside the container. Without nesting, the LXC container blocks nested namespace creation, causing Docker daemon startup to fail. |
| `keyctl = true` | Docker uses the Linux kernel keyring (`keyctl` syscall) for credential management and encrypted overlay storage. Without this, Docker operations involving secrets or certain storage drivers fail with permission errors. |

### Security Considerations

Privileged containers have full root access to the host kernel. Mitigations:

1. **Limit to infrastructure services only** -- do not run user-facing workloads in privileged LXC
2. **Use SSH key auth** -- no password-based access for ongoing management
3. **Firewall rules** -- restrict LXC container network access to required ports only
4. **Dedicated purpose** -- each privileged container should run a single, well-defined service

### Docker Installation in LXC

Docker CE installs normally inside a properly configured LXC container. No special Docker daemon flags are needed:

```bash
# Standard Docker CE installation (Ubuntu 24.04)
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

Docker Compose (v2, plugin form) is included via `docker-compose-plugin`. Use `docker compose` (space, not hyphen).

### Docker-in-LXC Gotchas

Several non-obvious issues arise when running Docker inside LXC containers, particularly during provisioning and re-provisioning.

**AppArmor removal:**

Docker checks for the AppArmor kernel module at startup, not just whether the `apparmor` service is running. Disabling the service with `systemctl disable apparmor` is insufficient. Remove the package entirely:

```bash
apt-get remove --purge -y apparmor
```

The host's AppArmor already confines the LXC container, so the in-guest AppArmor package is redundant. Alternatively, add `security_opt: [apparmor:unconfined]` to individual Docker Compose services.

**GPG keyring hang on re-provision:**

The `gpg --dearmor` command used during Docker's GPG key import can hang when Docker is already installed (the GPG keyring is locked or stdin blocks). Guard the entire Docker installation block with an idempotency check:

```bash
if ! command -v docker &>/dev/null; then
  # Full Docker CE installation here
  apt-get install -y ca-certificates curl gnupg
  # ...
fi
```

**Compose service networking:**

Docker Compose services running in LXC cannot reach each other via `localhost`. Each container has its own network namespace. Use Docker Compose service names as hostnames:

```yaml
# Wrong: localhost:11220
# Correct: connect-api:11220
services:
  connect-sync:
    environment:
      OP_HTTP_PORT: "11220"
      OP_BUS_PEERS: "connect-api:11220"
```

**Credentials file permissions:**

The 1Password Connect containers run internally as `opuser` (UID 999). A credentials file with `chmod 600` (owner-only) is unreadable by this non-root user. Use `chmod 644`:

```bash
chmod 644 /opt/op-connect/1password-credentials.json
chown 999:999 /opt/op-connect/data
```

## LXC Container Resource (Terraform)

The `proxmox_virtual_environment_container` resource manages LXC containers. It differs from the VM resource (`proxmox_virtual_environment_vm`) in several important ways.

### LXC Template Download

LXC uses a different template mechanism than VMs. Templates are system images (`.tar.zst`) downloaded via `content_type = "vztmpl"`:

```hcl
resource "proxmox_virtual_environment_download_file" "lxc_template" {
  for_each = var.instances

  content_type = "vztmpl"                    # NOT "iso" or "import"
  datastore_id = "local"                     # Must support vztmpl content type
  node_name    = each.key
  url          = "http://download.proxmox.com/images/system/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}
```

**Key differences from VM templates:**

| Aspect | VM Template | LXC Template |
|--------|------------|--------------|
| Content type | `iso` or `import` | `vztmpl` |
| Image format | `.qcow2`, `.img`, `.iso` | `.tar.zst`, `.tar.gz` |
| Storage | Needs `import` content type (e.g., Proxmox_NAS) | Needs `vztmpl` content type (usually `local`) |
| Template creation | Download image + create VM + convert to template | Download system tarball directly |
| Reference in resource | `clone { vm_id = ... }` | `operating_system { template_file_id = ... }` |
| Source | Cloud images (Ubuntu, Debian, etc.) | Proxmox system images (`download.proxmox.com/images/system/`) |

**Discovering available templates:**

```bash
# List available LXC templates from Proxmox repos
pveam available --section system | grep ubuntu-24
```

### Resource Structure

```hcl
resource "proxmox_virtual_environment_container" "example" {
  description   = "Service description -- managed by Terraform"
  node_name     = "pve-node-1"
  vm_id         = 200
  start_on_boot = true
  started       = true

  unprivileged = false        # Required for Docker-in-LXC
  features {
    nesting = true
    keyctl  = true
  }

  # Boot ordering (lower = earlier)
  startup {
    order      = "1"          # Boot before VMs (default order is higher)
    up_delay   = "30"         # Seconds to wait after starting before next
    down_delay = "15"         # Seconds to wait during shutdown
  }

  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.lxc_template["pve-node-1"].id
    type             = "ubuntu"
  }

  cpu {
    cores = 1
  }

  memory {
    dedicated = 512           # MB
  }

  disk {
    datastore_id = "local-lvm"
    size         = 8          # GB
  }

  initialization {
    hostname = "my-container"

    ip_config {
      ipv4 {
        address = "10.0.0.70/24"
        gateway = "10.0.0.1"
      }
    }

    # SSH key + password (password required by provider even if SSH is primary)
    user_account {
      keys     = [trimspace(var.ssh_public_key)]
      password = "changeme"
    }
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }
}
```

### LXC vs VM: Key Differences

| Feature | VM (`proxmox_virtual_environment_vm`) | LXC (`proxmox_virtual_environment_container`) |
|---------|--------------------------------------|----------------------------------------------|
| Cloud-init | Full support (`initialization` + `user_data_file_id`) | No cloud-init; `initialization` sets hostname/network/user only |
| Provisioning | Cloud-init runcmd, packages, write_files | Must use `null_resource` with SSH provisioners |
| Guest agent | QEMU guest agent for state feedback | No equivalent; container state is visible to host directly |
| Boot mechanism | BIOS/UEFI boot of full OS | Shares host kernel, starts init process |
| Resource overhead | Full OS kernel + QEMU overhead | Minimal: shared kernel, no hypervisor layer |
| Template type | VM template (clone) | System tarball (vztmpl) |
| Disk | Virtual disks (SCSI, IDE, VirtIO) | rootfs (bind mount or LVM thin volume) |

## Provisioning Without Cloud-Init

LXC containers in the bpg/proxmox provider do not support cloud-init. The `initialization` block only sets hostname, network configuration, and root/user credentials. For software installation and configuration, use `null_resource` with SSH provisioners.

### The Separation Pattern

Provisioning is kept in a separate `null_resource` (not inline provisioners on the container resource) for two critical reasons:

1. **Provisioner failures do not taint the container** -- a failed `apt-get install` does not mark the LXC container for destruction on next apply
2. **Re-runnable** -- use `terraform taint` on just the null_resource to re-provision without recreating the container

```hcl
resource "null_resource" "provision" {
  for_each = var.instances

  depends_on = [proxmox_virtual_environment_container.example]

  triggers = {
    container_id = proxmox_virtual_environment_container.example[each.key].id
  }

  connection {
    type        = "ssh"
    host        = each.value.ip
    user        = "root"
    private_key = var.ssh_private_key
  }

  # Upload configuration files
  provisioner "file" {
    source      = "${path.module}/templates/config-file"
    destination = "/tmp/config-file"
  }

  # Upload templated configuration
  provisioner "file" {
    content = templatefile("${path.module}/templates/config.tftpl", {
      variable = each.value.setting
    })
    destination = "/tmp/config"
  }

  # Execute setup
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/setup.sh",
      "/tmp/setup.sh",
    ]
  }
}
```

### Re-provisioning

```bash
# Re-run provisioning for a specific node without recreating the container
terraform taint 'module.op_connect.null_resource.provision["node-01"]'
terraform apply
```

### Provisioning Script Pattern

Keep the setup script as a single idempotent bash script uploaded via the `file` provisioner:

```bash
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Install packages
apt-get update -qq
apt-get install -y -qq <packages>

# Deploy configuration files from /tmp to final locations
mv /tmp/config-file /etc/service/config-file
mv /tmp/service-unit /etc/systemd/system/service.service

# Enable and start services
systemctl daemon-reload
systemctl enable --now service

# Health check with retry loop
for i in $(seq 1 12); do
  if curl -sf http://localhost:PORT/health >/dev/null 2>&1; then
    echo "Service is healthy!"
    exit 0
  fi
  echo "Waiting for service to start... ($i/12)"
  sleep 5
done

echo "WARNING: Service did not become healthy within 60s"
exit 1
```

Key practices:

- `set -euo pipefail` for fail-fast behavior
- `DEBIAN_FRONTEND=noninteractive` prevents apt prompts during SSH provisioning
- Health check loop with timeout at the end to catch startup failures
- Files staged to `/tmp` by provisioners, then moved to final locations by the script

## Keepalived VRRP Failover

Keepalived provides Virtual Router Redundancy Protocol (VRRP) for automatic VIP failover between LXC containers. This is the pattern used for HA services that need a stable IP address.

### Architecture

```
              VIP: 10.0.0.72
              (keepalived floats)
                    |
      +-------------+-------------+
      |                           |
  Node A (CT 200)           Node B (CT 201)
  10.0.0.70              10.0.0.71
  MASTER (priority 100)    BACKUP (priority 90)
  Service + keepalived     Service + keepalived
```

### Unicast vs Multicast

Keepalived supports two VRRP advertisement modes:

| Mode | Default | LXC Compatible | Proxmox-Friendly |
|------|---------|----------------|-------------------|
| Multicast (224.0.0.18) | Yes | Unreliable | No -- multicast often blocked or misrouted between VMs/containers |
| Unicast | No (explicit config) | Yes | Yes -- point-to-point, no switch/bridge multicast concerns |

**Always use unicast peers in Proxmox environments.** Multicast VRRP advertisements may be silently dropped by the Linux bridge (`vmbr0`), Proxmox firewall, or upstream switch ACLs. Unicast is deterministic and reliable.

### Configuration Template

```
vrrp_script check_service {
    script "/usr/bin/curl -sf http://localhost:8080/heartbeat"
    interval 5          # Check every 5 seconds
    weight -20          # Subtract 20 from priority on failure
    fall 2              # Require 2 consecutive failures to mark down
    rise 2              # Require 2 consecutive successes to mark up
}

vrrp_instance VI_SERVICE {
    state ${state}                    # MASTER or BACKUP
    interface eth0                    # LXC network interface
    virtual_router_id 72             # Must be unique on the subnet (1-255)
    priority ${priority}             # MASTER: 100, BACKUP: 90
    advert_int 1                     # VRRP advertisement interval (seconds)

    # Unicast peers -- required for reliable operation in LXC
    unicast_src_ip ${src_ip}         # This container's real IP
    unicast_peer {
        ${peer_ip}                   # Other container's real IP
    }

    authentication {
        auth_type PASS
        auth_pass myservice          # Simple password (not security-critical on LAN)
    }

    virtual_ipaddress {
        ${vip}/24                    # The floating VIP
    }

    track_script {
        check_service
    }
}
```

### Peer IP Computation in Terraform

For a `for_each`-based deployment, compute peer IPs dynamically:

```hcl
locals {
  instances = {
    "pve-node-1" = { ip = "10.0.0.70", state = "MASTER", priority = 100 }
    "pve-node-2" = { ip = "10.0.0.71", state = "BACKUP", priority = 90 }
  }

  # Each node's peer is the other node's IP
  peer_ips = {
    for node, inst in local.instances :
    node => [for other_node, other_inst in local.instances : other_inst.ip if other_node != node][0]
  }
}
```

### Health Check Script Design

The `vrrp_script` block defines the health check. Design principles:

1. **Check the actual service**, not just the container -- `curl` the application health endpoint
2. **Use `fall 2`** -- avoid flapping on transient failures (requires 2 consecutive failures)
3. **Use `rise 2`** -- avoid premature failback (requires 2 consecutive successes)
4. **`weight -20`** should exceed the priority gap between MASTER and BACKUP (100 - 90 = 10, so -20 ensures failover)
5. **Keep interval reasonable** (5s) -- too frequent adds overhead, too slow delays failover

### Failover Timing

With the configuration above:

- **Detection:** 2 failed checks x 5s interval = 10s to detect failure
- **VRRP advertisement:** 1s interval, 3 missed advertisements = 3s for BACKUP to notice
- **Total failover time:** approximately 13-15 seconds

### Systemd Integration

Run Docker services via a systemd unit so keepalived can track the service lifecycle:

```ini
[Unit]
Description=Service Name
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/service
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
```

**Why `Type=oneshot` + `RemainAfterExit=yes`:** Docker Compose detaches (`-d`), so the `ExecStart` process exits immediately. `RemainAfterExit=yes` keeps the unit in "active" state after the process exits. This allows `systemctl status` and keepalived to correctly report the service as running.

## Boot Order Strategy

LXC containers that provide infrastructure services (secrets, DNS, etc.) must boot before the K3s VMs that depend on them:

```hcl
startup {
  order      = "1"    # Low number = boots first
  up_delay   = "30"   # Wait 30s after start before booting next tier
  down_delay = "15"   # Graceful shutdown delay
}
```

Typical boot order for this homelab:

| Order | Resource | Rationale |
|-------|----------|-----------|
| 1 | 1Password Connect LXC containers | Secrets must be available before anything else |
| 2 (default) | K3s server VMs | Control plane needs Connect for ESO secrets |
| 3 (default) | K3s agent VMs | Workers join after control plane is ready |

The `up_delay` ensures the service inside the container is fully started before the next boot tier begins. 30 seconds allows Docker to pull images (on first boot) or start cached containers.

## Module Structure

The recommended file layout for an LXC-based Terraform module:

```
modules/service-name/
  providers.tf           # Required providers (bpg/proxmox, hashicorp/null)
  variables.tf           # Input variables (credentials, sizing, network)
  outputs.tf             # Service URL (VIP), instance details, health check commands
  service-cluster.tf     # LXC containers + null_resource provisioners
  templates/
    docker-compose.yml   # Static Docker Compose configuration
    config.tftpl         # Templated configuration (keepalived, app config, etc.)
    setup.sh             # Idempotent provisioning script
    service.service      # Systemd unit file
```

## NVIDIA GPU Device Passthrough to LXC

For AI/ML workloads requiring GPU access, the recommended approach is to install NVIDIA drivers on the Proxmox host and bind-mount the device nodes into a privileged LXC container. This avoids KVM VFIO passthrough (which has hardware-specific incompatibilities -- see [deployment-troubleshooting.md](./deployment-troubleshooting.md) for details on RTX 3060 + X299 failures).

### Why LXC over VFIO

| Aspect | KVM VFIO passthrough | LXC + host driver |
|--------|---------------------|-------------------|
| Driver runs in | Guest VM | Host kernel (shared with container) |
| IOMMU/VFIO required | Yes | No |
| Hardware compatibility | Issues with Ampere + X299/Skylake-X | Works wherever host driver works |
| Overhead | Full VM + QEMU | Near-native (shared kernel) |
| Isolation | Full VM isolation | Container isolation (less than VM) |
| Reset between workloads | Requires GPU reset (problematic) | Host driver handles it |

### Host Prerequisites

NVIDIA drivers must be installed on the Proxmox host before the LXC container is created:

```bash
# On the Proxmox host (Debian-based)
apt-get install -y linux-headers-$(uname -r)
# Install NVIDIA driver from Debian non-free or NVIDIA .run installer
# Verify:
nvidia-smi
```

### Container Configuration

The LXC container must be privileged (UID remapping in unprivileged containers breaks cgroup device allow rules):

```hcl
resource "proxmox_virtual_environment_container" "gpu_workload" {
  unprivileged = false   # Required: UID remapping breaks NVIDIA device access

  features {
    nesting = true       # Required for Docker inside LXC
  }
  # ... other config
}
```

### Device Passthrough via null_resource

The bpg/proxmox provider does not expose `lxc.cgroup2.devices.allow` or `lxc.mount.entry` fields. Write them directly to `/etc/pve/lxc/<vmid>.conf` via SSH after container creation.

**Important: NVIDIA driver version affects device layout.**

- **NVIDIA <= 565.x (older):** `nvidia-uvm` uses major `236`; `/dev/nvidia-modeset` exists as a standalone device at `10:235`
- **NVIDIA 580+:** `nvidia-uvm` major is dynamically assigned (e.g., `510` on kernel 6.17); `/dev/nvidia-modeset` does NOT exist as a standalone device

Always verify device nodes on the host before writing cgroup allow entries:

```bash
# Check which /dev/nvidia* nodes exist on the host
ls -la /dev/nvidia*

# Check the actual nvidia-uvm major number (NVIDIA 580+)
cat /sys/module/nvidia_uvm/parameters/uvm_dev_major
```

```hcl
resource "null_resource" "nvidia_lxc_passthrough" {
  count      = var.gpu_passthrough_enabled ? 1 : 0
  depends_on = [proxmox_virtual_environment_container.gpu_workload]

  connection {
    type        = "ssh"
    host        = var.node_host   # Proxmox host IP
    user        = "root"
    private_key = var.ssh_private_key
  }

  provisioner "remote-exec" {
    inline = [
      # Idempotent: remove existing lxc.* entries then re-add
      "sed -i '/^lxc\\./d' /etc/pve/lxc/${var.vm_id}.conf",
      # cgroup device allowlist (character devices)
      # 195:* = /dev/nvidia0, /dev/nvidiactl (stable across driver versions)
      # *:*   = all character devices (simplest for trusted privileged container)
      #         Use this when nvidia-uvm major is dynamic (NVIDIA 580+ on kernel 6.17+)
      # NOTE: Do NOT add c 236:* for NVIDIA 580+ -- that major is reassigned elsewhere
      # NOTE: Do NOT add c 10:235 or nvidia-modeset bind-mount for NVIDIA 580+ --
      #       /dev/nvidia-modeset does not exist as a standalone device in this driver series
      "echo 'lxc.cgroup2.devices.allow: c 195:* rwm' >> /etc/pve/lxc/${var.vm_id}.conf",
      "echo 'lxc.cgroup2.devices.allow: c *:* rwm' >> /etc/pve/lxc/${var.vm_id}.conf",
      # Bind-mount device nodes (optional = don't fail if driver not loaded or device absent)
      # nvidia-uvm nodes are created lazily -- ensure nvidia-uvm-init.service runs first
      "echo 'lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file' >> /etc/pve/lxc/${var.vm_id}.conf",
      "echo 'lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file' >> /etc/pve/lxc/${var.vm_id}.conf",
      "echo 'lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file' >> /etc/pve/lxc/${var.vm_id}.conf",
      "echo 'lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file' >> /etc/pve/lxc/${var.vm_id}.conf",
    ]
  }
}
```

**Key details:**

- `optional,create=file` prevents container start failure if the host driver is not loaded (e.g., during maintenance). Without `optional`, a missing `/dev/nvidia0` causes the container to refuse to start.
- The `sed -i '/^lxc\./d'` line makes the provisioner idempotent -- removes any previous entries before re-adding.
- The Proxmox cluster filesystem (`/etc/pve/lxc/`) is writable from any cluster node, but writing on the owning node is cleanest.
- `nvidia-uvm` device nodes (`/dev/nvidia-uvm`, `/dev/nvidia-uvm-tools`) are created lazily. A host systemd service must run `nvidia-smi` before LXC containers start to ensure the nodes exist when the bind-mounts are applied. See [deployment-troubleshooting.md](./deployment-troubleshooting.md) for the `nvidia-uvm-init.service` pattern.

### pct exec Instability Warning

When provisioning or managing a privileged LXC container with NVIDIA device passthrough on certain hardware (confirmed: X299/Skylake-X, kernel 6.17), using `pct exec <vmid> -- <cmd>` for package installation can cause repeatable host kernel panics. This crash pattern is distinct from GPU passthrough -- it occurs even with no GPU workload running.

**Workaround:** SSH directly into the container (`ssh root@<container-ip>`) rather than using `pct exec`. Direct SSH does not trigger the crash. The Terraform `null_resource` provisioner using the `connection` block SSH approach is also unaffected.

### Inside the Container

Install `nvidia-container-toolkit` to enable Docker/Podman GPU access:

```bash
# Install nvidia-container-toolkit inside the LXC
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor \
  -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update && apt-get install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

# Verify GPU access inside container
nvidia-smi
docker run --rm --gpus all nvidia/cuda:12.3.0-base-ubuntu22.04 nvidia-smi
```

### NVIDIA Driver Version Considerations

The NVIDIA driver version on the Proxmox host must be compatible with the kernel version. On Proxmox VE (Debian-based) with a PVE kernel (e.g., `6.17.x-pve`):

- NVIDIA drivers ship two series: **production** (currently 550.x) and **new feature** (currently 580.x)
- The `.run` installer from NVIDIA requires kernel headers matching the running kernel
- On Debian Trixie + PVE kernel, use `proxmox-headers-$(uname -r)` to get the correct headers package
- Verify kernel module loads after install: `modprobe nvidia && nvidia-smi`

**NVIDIA 580+ behavioural differences relevant to LXC passthrough:**

| Feature | NVIDIA <= 565.x | NVIDIA 580.x+ |
|---------|-----------------|---------------|
| nvidia-uvm major number | Stable (236) | Dynamic (kernel-assigned; e.g., 510 on kernel 6.17) |
| /dev/nvidia-modeset | Exists at 10:235 | Does NOT exist as a standalone device node |
| nvidia-uvm device creation | Eager (at module load) | Lazy (at first userspace access) |

After installing any NVIDIA driver, always verify the actual device layout before writing LXC config:

```bash
ls -la /dev/nvidia*
cat /proc/devices | grep nvidia
cat /sys/module/nvidia_uvm/parameters/uvm_dev_major  # Empty if uvm not yet initialised
nvidia-smi  # This forces uvm device creation
ls -la /dev/nvidia*  # Re-check after nvidia-smi
```
