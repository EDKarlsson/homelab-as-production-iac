# K3s Cluster Infrastructure Configuration
# Deploys 8 VMs across 5 Proxmox nodes for K3s cluster (5 agents + 3 servers)
# PostgreSQL HA is managed by the separate pg-ha module

locals {
  # K3s cluster configuration
  k3s_cluster_name = "homelab-k3s-cluster"

  server_nodes = [
    "node-02",
    "node-03",
    "node-04"
  ]

  agent_nodes = tomap({
    "node-02" = {
      cpu_cores = 6
      memory_gb = 26
      disk_gb   = 100
    },
    "node-03" = {
      cpu_cores = 8
      memory_gb = 20
      disk_gb   = 300
    },
    "node-04" = {
      cpu_cores = 8
      memory_gb = 24
      disk_gb   = 300
    },
    "node-01" = {
      cpu_cores = 12
      memory_gb = 24
      disk_gb   = 500
    },
    "node-05" = {
      cpu_cores = 10
      memory_gb = 60
      disk_gb   = 1000
    }
  })

  k3s_server_ips = {
    for i, node in local.server_nodes : node => "10.0.0.${50 + i}"
  }

  k3s_agent_ips = {
    for i, node in local.agent_nodes : i => "10.0.0.${60 + index(keys(local.agent_nodes), i)}"
  }

  # Network configuration (VLAN02-Homelab)
  k3s_network = {
    vlan_id     = 2
    subnet      = "10.0.0.0/24"
    gateway     = "10.0.0.1",
    dns_servers = ["8.8.8.8", "8.8.4.4"]
  }

}


# QEMU Guest Agent Configuration
# ──────────────────────────────
# The bpg/proxmox provider queries each VM's QEMU guest agent during
# terraform plan/apply to read network interfaces. If the agent is not
# running, every refresh hangs until timeout — with 9 VMs at 15m each,
# that's potentially 135 minutes of wasted time.
#
# Requirements:
#   1. VM template must include `qemu-guest-agent` package
#   2. Cloud-init installs the package, but Ubuntu 24.04 does NOT
#      auto-start it (it uses SysV init, not a systemd [Install] section)
#   3. The agent activates via Proxmox's virtio-serial channel when
#      agent.enabled = true in the VM config
#
# Fix applied:
#   - Manually started agent on all running VMs:
#       scripts/k8s/k3s-ssh.sh all 'sudo systemctl enable --now qemu-guest-agent'
#   - Reduced timeout from 15m to 2m (agent responds in <1s when running)
#   - Result: terraform plan dropped from ~10 minutes to ~1.4 seconds
#
# IMPORTANT: Do NOT modify cloud-init templates (*.yml.tftpl) for running
# VMs — any template content change forces snippet replacement, which
# cascades to user_data_file_id change, which forces VM DESTRUCTION and
# recreation. Cloud-init only runs at first boot anyway.

# K3s Server VMs (Control Plane)
resource "proxmox_virtual_environment_vm" "k3s_servers" {
  for_each = toset(local.server_nodes)

  name        = "homelab-server-${each.key}"
  description = "K3s Cluster Server Node - ${each.key}"
  node_name   = each.key
  vm_id       = 500 + index(local.server_nodes, each.key)

  clone {
    vm_id        = var.k3s_template_vm_id
    node_name    = var.k3s_template_node_name
    datastore_id = var.virtual_environment_datastore_id
    full         = true
  }

  agent {
    enabled = true
    timeout = "2m"
  }

  cpu {
    cores   = 4
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096 # 4GB RAM for control plane
  }

  network_device {
    bridge = "vmbr0"
  }

  disk {
    datastore_id = var.virtual_environment_datastore_id
    interface    = "scsi0"
    size         = 40 # 40GB for OS and K3s
    cache        = "writethrough"
    iothread     = true
  }

  initialization {
    dns {
      servers = ["8.8.8.8", "8.8.4.4"]
      domain  = "homelab.local"
    }

    ip_config {
      ipv4 {
        address = "${local.k3s_server_ips[each.key]}/24"
        gateway = local.k3s_network.gateway
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.k3s_server_cloud_config[each.key].id
  }

  tags = ["k3s", "server", "homelab", "infrastructure"]

  lifecycle {
    ignore_changes        = [initialization]
    create_before_destroy = true
  }
}

# K3s Agent VMs (Worker Nodes)  
resource "proxmox_virtual_environment_vm" "k3s_agents" {
  for_each = local.agent_nodes

  name        = "homelab-agent-${each.key}"
  description = "K3s Cluster Agent Node - ${each.key}"
  node_name   = each.key
  vm_id       = 510 + index(keys(local.agent_nodes), each.key)

  clone {
    vm_id        = var.k3s_template_vm_id
    node_name    = var.k3s_template_node_name
    datastore_id = var.virtual_environment_datastore_id
    full         = true
  }

  agent {
    enabled = true
    timeout = "2m"
  }

  cpu {
    cores   = each.value.cpu_cores
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = each.value.memory_gb * 1024 # Convert GB to MB
  }

  network_device {
    bridge = "vmbr0"
  }

  disk {
    datastore_id = var.virtual_environment_datastore_id
    interface    = "scsi0"
    size         = each.value.disk_gb
    cache        = "writethrough"
    iothread     = true
  }

  initialization {
    dns {
      servers = ["8.8.8.8", "8.8.4.4"]
      domain  = "homelab.local"
    }

    ip_config {
      ipv4 {
        address = "${local.k3s_agent_ips[each.key]}/24"
        gateway = local.k3s_network.gateway
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.k3s_agent_cloud_config[each.key].id
  }

  tags = ["k3s", "agent", "homelab", "infrastructure"]

  lifecycle {
    ignore_changes        = [initialization]
    create_before_destroy = true
  }
}
