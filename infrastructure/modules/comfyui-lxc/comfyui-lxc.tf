locals {
  ct_tags = ["comfyui", "ai", "docker", "homelab", "infrastructure"]
}

resource "proxmox_virtual_environment_container" "comfyui" {
  node_name   = var.node_name
  vm_id       = var.vm_id
  description = "ComfyUI LXC container (privileged, Docker + host NVIDIA GPU passthrough)"
  tags        = local.ct_tags

  # Must be privileged: NVIDIA device bind-mounts require root namespace access.
  # Unprivileged containers remap UIDs which breaks cgroup device allow rules.
  unprivileged = false

  start_on_boot = var.on_boot
  started       = var.started

  features {
    # Required for Docker inside LXC (nested namespaces).
    nesting = true
  }

  initialization {
    hostname = var.hostname

    dns {
      servers = var.dns_servers
      domain  = var.domain
    }

    ip_config {
      ipv4 {
        address = "${var.ip_address}/24"
        gateway = var.gateway
      }
    }

    user_account {
      keys = [var.ssh_public_key]
    }
  }

  cpu {
    cores = var.cpu_cores
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = var.datastore_id
    size         = var.disk_size_gb
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  operating_system {
    template_file_id = var.template_file_id
    type             = "ubuntu"
  }
}

# Append NVIDIA device passthrough config to the LXC container config file.
#
# The bpg/proxmox provider does not expose raw lxc.cgroup2.devices.allow or
# lxc.mount.entry fields, so we write them directly to /etc/pve/lxc/<id>.conf
# via SSH on the Proxmox host. Proxmox cluster filesystem (/etc/pve/lxc/) is
# writeable from any node, but writing on the owning node is cleanest.
#
# cgroup2 device allowlist: "c *:* rwm" covers all character devices regardless of
# major number assignment. nvidia-uvm's major is dynamically assigned by the kernel
# (was 236 in older drivers; became 510 on kernel 6.17 + NVIDIA 580+), so a specific
# major entry would break across kernel/driver upgrades. Privileged LXC + Docker
# already requires broad device access; wildcard char device allowance is appropriate.
#
# The "optional,create=file" flags prevent container start failure if the host
# driver isn't loaded yet (e.g., during host maintenance / driver reinstall).
# NOTE: /dev/nvidia-uvm is created lazily — ensure nvidia-device-nodes.service runs
# on the host before the LXC starts (writes device nodes via nvidia-smi on boot).
resource "null_resource" "nvidia_lxc_passthrough" {
  count = var.gpu_passthrough_enabled ? 1 : 0

  depends_on = [proxmox_virtual_environment_container.comfyui]

  triggers = {
    container_id = proxmox_virtual_environment_container.comfyui.id
    gpu_enabled  = var.gpu_passthrough_enabled
  }

  connection {
    type        = "ssh"
    host        = var.node_host
    user        = "root"
    agent       = false
    private_key = var.ssh_private_key
  }

  provisioner "remote-exec" {
    inline = [
      # Idempotent: remove any existing lxc.* entries, then re-add clean.
      "sed -i '/^lxc\\./d' /etc/pve/lxc/${var.vm_id}.conf",
      # cgroup2 device allowlist: wildcard covers all char devices (handles dynamic major numbers)
      "echo 'lxc.cgroup2.devices.allow: c *:* rwm' >> /etc/pve/lxc/${var.vm_id}.conf",
      # Bind-mount device nodes from host into container namespace
      # /dev/nvidia0 and /dev/nvidia1 — index depends on host driver probe order (both bound)
      # Note: /dev/nvidia-modeset removed — NVIDIA 580+ accesses modeset via ioctl on nvidiactl
      "echo 'lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file' >> /etc/pve/lxc/${var.vm_id}.conf",
      "echo 'lxc.mount.entry: /dev/nvidia1 dev/nvidia1 none bind,optional,create=file' >> /etc/pve/lxc/${var.vm_id}.conf",
      "echo 'lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file' >> /etc/pve/lxc/${var.vm_id}.conf",
      "echo 'lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file' >> /etc/pve/lxc/${var.vm_id}.conf",
      "echo 'lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file' >> /etc/pve/lxc/${var.vm_id}.conf",
    ]
  }
}
