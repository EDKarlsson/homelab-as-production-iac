# Cloud-config templates for K3s cluster VMs

# K3s Server Cloud-config Template
resource "proxmox_virtual_environment_file" "k3s_server_cloud_config" {
  for_each = toset(local.server_nodes)

  content_type = "snippets"
  datastore_id = var.virtual_environment_snippet_datastore_id
  node_name    = each.key

  source_raw {
    data = templatefile("${path.module}/cloud-configs/k3s-server.yml.tftpl", {
      hostname             = "homelab-server-${each.key}"
      username             = var.k3s_username
      ssh_public_key       = var.ssh_public_key
      k3s_version          = var.k3s_version
      k3s_token            = var.k3s_cluster_token
      server_ip            = local.k3s_server_ips[each.key]
      postgres_ip          = var.postgres_ip
      postgres_password    = var.postgres_password
      nexus_apt_mirror_url = var.nexus_apt_mirror_url
    })

    file_name = "k3s-server-${each.key}.yml"
  }
}

# K3s Agent Cloud-config Template  
resource "proxmox_virtual_environment_file" "k3s_agent_cloud_config" {
  for_each = local.agent_nodes

  content_type = "snippets"
  datastore_id = var.virtual_environment_snippet_datastore_id
  node_name    = each.key

  source_raw {
    data = templatefile("${path.module}/cloud-configs/k3s-agent.yml.tftpl", {
      hostname             = "homelab-agent-${each.key}"
      username             = var.k3s_username
      ssh_public_key       = var.ssh_public_key
      k3s_version          = var.k3s_version
      k3s_token            = var.k3s_cluster_token
      server_url           = "https://${local.k3s_server_ips[local.server_nodes[0]]}:6443"
      nexus_apt_mirror_url = var.nexus_apt_mirror_url
    })

    file_name = "k3s-agent-${each.key}.yml"
  }
}
