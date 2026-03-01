locals {
  vm_tags = ["comfyui", "ai", "docker", "homelab", "infrastructure"]
  effective_machine = var.machine_type != "" ? var.machine_type : (
    var.gpu_passthrough_enabled ? "q35" : "pc"
  )
  effective_bios = var.bios_type != "" ? var.bios_type : (
    var.gpu_passthrough_enabled ? "ovmf" : "seabios"
  )
  hostpci_devices = var.gpu_passthrough_enabled ? concat(
    var.gpu_pci_id != "" ? [{
      device = "hostpci0"
      id     = var.gpu_pci_id
      xvga   = var.gpu_xvga
    }] : [],
    var.gpu_audio_pci_id != "" ? [{
      device = "hostpci1"
      id     = var.gpu_audio_pci_id
      xvga   = false
    }] : []
  ) : []
}

resource "proxmox_virtual_environment_file" "comfyui_cloud_config" {
  content_type = "snippets"
  datastore_id = var.snippet_datastore_id
  node_name    = var.node_name

  source_raw {
    data = templatefile("${path.module}/cloud-configs/comfyui.yml.tftpl", {
      hostname       = var.vm_name
      username       = var.vm_username
      ssh_public_key = var.ssh_public_key
      domain         = var.domain
      base_image     = var.comfyui_base_image
      source_ref     = var.comfyui_source_ref
      port           = var.comfyui_port
      ip_address     = var.ip_address
      use_gpu        = var.gpu_passthrough_enabled
    })

    file_name = "comfyui-${var.vm_id}.yml"
  }
}

resource "proxmox_virtual_environment_vm" "comfyui" {
  name        = var.vm_name
  description = "ComfyUI VM (Docker Compose, source-built image)"
  node_name   = var.node_name
  vm_id       = var.vm_id
  machine     = local.effective_machine
  bios        = local.effective_bios
  on_boot     = var.on_boot
  started     = var.started

  clone {
    vm_id        = var.template_vm_id
    node_name    = var.template_node_name
    datastore_id = var.datastore_id
    full         = true
  }

  agent {
    enabled = true
    timeout = "2m"
  }

  cpu {
    cores   = var.cpu_cores
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.memory_mb
  }

  network_device {
    bridge = "vmbr0"
  }

  dynamic "hostpci" {
    for_each = local.hostpci_devices
    content {
      device = hostpci.value.device
      id     = hostpci.value.id
      pcie   = var.gpu_pcie
      rombar = var.gpu_rombar
      xvga   = hostpci.value.xvga
    }
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.disk_size_gb
    cache        = "writethrough"
    iothread     = true
  }

  initialization {
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

    user_data_file_id = proxmox_virtual_environment_file.comfyui_cloud_config.id
  }

  tags = local.vm_tags

  lifecycle {
    # Prevent cloud-init snippet content changes from forcing a VM replacement.
    ignore_changes        = [initialization]
    create_before_destroy = true
  }
}
