# PostgreSQL HA Cluster — 2 VMs with keepalived VIP failover
#
# Architecture:
#   node-01  (VM 520, 10.0.0.45) — Primary, keepalived MASTER (priority 100)
#   node-05 (VM 521, 10.0.0.46) — Standby, keepalived BACKUP (priority 90)
#   VIP: 10.0.0.44 (floats via keepalived VRRP)
#
# Streaming replication: primary → standby (async WAL)
# Failover: keepalived detects pg_isready failure, promotes standby

locals {
  cluster_name = "homelab-psql"

  instances = {
    "node-01" = {
      vm_id    = 520
      ip       = "10.0.0.45"
      role     = "primary"
      state    = "MASTER"
      priority = 100
    }
    "node-05" = {
      vm_id    = 521
      ip       = "10.0.0.46"
      role     = "standby"
      state    = "BACKUP"
      priority = 90
    }
  }

  # Compute peer IPs for keepalived unicast (each node needs the other's IP)
  peer_ips = {
    for node, inst in local.instances :
    node => [for other_node, other_inst in local.instances : other_inst.ip if other_node != node][0]
  }

  network = {
    gateway     = var.gateway
    dns_servers = ["8.8.8.8", "8.8.4.4"]
    domain      = "homelab.local"
  }
}

# --- Cloud-Config Snippets ---
# Each node gets a role-specific cloud-init template (primary vs standby)
resource "proxmox_virtual_environment_file" "pg_cloud_config" {
  for_each = local.instances

  content_type = "snippets"
  datastore_id = var.snippet_datastore_id
  node_name    = each.key

  source_raw {
    data = templatefile(
      "${path.module}/cloud-configs/postgresql-${each.value.role}.yml.tftpl",
      {
        hostname             = "${local.cluster_name}-${each.value.role}"
        username             = var.vm_username
        ssh_public_key       = var.ssh_public_key
        postgres_password    = var.postgres_password
        replication_password = var.replication_password
        primary_ip           = local.instances["node-01"].ip
        vip                  = var.vip
        node_ip              = each.value.ip
        peer_ip              = local.peer_ips[each.key]
        keepalived_state     = each.value.state
        keepalived_priority  = each.value.priority
      }
    )

    file_name = "postgresql-${each.value.role}-${each.key}.yml"
  }
}

# --- PostgreSQL VMs ---
resource "proxmox_virtual_environment_vm" "postgres" {
  for_each = local.instances

  name        = "${local.cluster_name}-${each.value.role}"
  description = "PostgreSQL ${each.value.role} (${each.value.state}) — managed by Terraform"
  node_name   = each.key
  vm_id       = each.value.vm_id

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
    cores   = 2
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096
  }

  network_device {
    bridge = "vmbr0"
  }

  # OS Disk
  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = 40
    cache        = "writethrough"
    iothread     = true
  }

  # Database Disk
  disk {
    datastore_id = var.datastore_id
    interface    = "scsi1"
    size         = 100
    cache        = "writethrough"
    iothread     = true
  }

  initialization {
    dns {
      servers = local.network.dns_servers
      domain  = local.network.domain
    }

    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = local.network.gateway
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.pg_cloud_config[each.key].id
  }

  tags = ["postgresql", "database", "ha", "homelab", "infrastructure"]

  lifecycle {
    # Cloud-init only runs on first boot. Snippet changes must not trigger
    # VM replacement — that would destroy a running PostgreSQL instance.
    ignore_changes        = [initialization]
    create_before_destroy = true
  }
}
