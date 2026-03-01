# HA 1Password Connect — 2 LXC containers with keepalived VIP failover
#
# Architecture:
#   node-01  (CT 200, 10.0.0.70) — MASTER, priority 100
#   node-05 (CT 201, 10.0.0.71) — BACKUP, priority 90
#   VIP: 10.0.0.72 (floats via keepalived VRRP)
#
# Each container runs Docker with connect-api + connect-sync containers
# and keepalived for automatic VIP failover on health check failure.

locals {
  instances = {
    "node-01" = {
      ct_id    = 200
      ip       = "10.0.0.70"
      state    = "MASTER"
      priority = 100
    }
    "node-05" = {
      ct_id    = 201
      ip       = "10.0.0.71"
      state    = "BACKUP"
      priority = 90
    }
  }

  # Compute peer IPs for keepalived unicast (each node needs the other's IP)
  peer_ips = {
    for node, inst in local.instances :
    node => [for other_node, other_inst in local.instances : other_inst.ip if other_node != node][0]
  }
}

# --- LXC Template ---
# Download Ubuntu 24.04 LXC template on each node
resource "proxmox_virtual_environment_download_file" "lxc_template" {
  for_each = local.instances

  content_type        = "vztmpl"
  datastore_id        = var.lxc_template_storage
  node_name           = each.key
  url                 = var.lxc_template_url
  overwrite_unmanaged = true
}

# --- LXC Containers ---
resource "proxmox_virtual_environment_container" "op_connect" {
  for_each = local.instances

  description   = "1Password Connect (${each.value.state}) — managed by Terraform"
  node_name     = each.key
  vm_id         = each.value.ct_id
  start_on_boot = true
  started       = true

  # Privileged container required for Docker-in-LXC
  unprivileged = false
  features {
    nesting = true
    keyctl  = true
  }

  # Boot before K3s VMs (which depend on Connect for secrets)
  startup {
    order      = "1"
    up_delay   = "30"
    down_delay = "15"
  }

  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.lxc_template[each.key].id
    type             = "ubuntu"
  }

  cpu {
    cores = var.lxc_cpu_cores
  }

  memory {
    dedicated = var.lxc_memory
  }

  disk {
    datastore_id = var.lxc_disk_storage
    size         = var.lxc_disk_size
  }

  initialization {
    hostname = "op-connect-${lower(each.value.state)}"

    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = var.gateway
      }
    }

    user_account {
      keys     = [trimspace(var.ssh_public_key)]
      password = "changeme" # Overridden by SSH key auth; required by provider
    }
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }
}

# --- Provisioning ---
# Separate from container resource so provisioner failures don't taint the LXC.
# Re-run with: terraform taint 'module.op_connect.null_resource.provision["node-01"]'
resource "null_resource" "provision" {
  for_each = local.instances

  depends_on = [proxmox_virtual_environment_container.op_connect]

  triggers = {
    container_id = proxmox_virtual_environment_container.op_connect[each.key].id
  }

  connection {
    type        = "ssh"
    host        = each.value.ip
    user        = "root"
    private_key = var.ssh_private_key
  }

  # Upload docker-compose.yml (static)
  provisioner "file" {
    source      = "${path.module}/templates/docker-compose.yml"
    destination = "/tmp/docker-compose.yml"
  }

  # Upload keepalived.conf (templated per-node)
  provisioner "file" {
    content = templatefile("${path.module}/templates/keepalived.conf.tftpl", {
      state    = each.value.state
      priority = each.value.priority
      src_ip   = each.value.ip
      peer_ip  = local.peer_ips[each.key]
      vip      = var.vip
    })
    destination = "/tmp/keepalived.conf"
  }

  # Upload systemd service (static)
  provisioner "file" {
    source      = "${path.module}/templates/op-connect.service"
    destination = "/tmp/op-connect.service"
  }

  # Upload setup script (static)
  provisioner "file" {
    source      = "${path.module}/templates/setup.sh"
    destination = "/tmp/setup.sh"
  }

  # Write credentials and run setup
  provisioner "remote-exec" {
    inline = [
      "echo '${var.op_credentials_b64}' > /tmp/op-credentials.b64",
      "chmod +x /tmp/setup.sh",
      "/tmp/setup.sh",
    ]
  }
}
