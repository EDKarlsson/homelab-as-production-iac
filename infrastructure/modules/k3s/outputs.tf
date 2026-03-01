# Infrastructure Outputs
# Asgard K3s Cluster - Infrastructure Information

# K3s Server Node Information
output "k3s_servers" {
  description = "K3s server node information"
  value = {
    for node in local.server_nodes : node => {
      name       = "homelab-server-${node}"
      vm_id      = 500 + index(local.server_nodes, node)
      ip_address = local.k3s_server_ips[node]
      node_name  = node
      role       = "server"
    }
  }
}

# K3s Agent Node Information
output "k3s_agents" {
  description = "K3s agent node information"
  value = {
    for i, node in local.agent_nodes : i => {
      name       = "homelab-agent-${i}"
      vm_id      = 510 + index(keys(local.agent_nodes), i)
      ip_address = local.k3s_agent_ips[i]
      node_name  = i
      role       = "agent"
    }
  }
}

# Cluster Overview
output "cluster_overview" {
  description = "K3s cluster overview and connection information"
  value = {
    cluster_name      = local.k3s_cluster_name
    total_nodes       = length(local.server_nodes) + length(keys(local.agent_nodes))
    server_nodes      = length(local.server_nodes)
    agent_nodes       = length(keys(local.agent_nodes))
    network_vlan      = local.k3s_network.vlan_id
    network_subnet    = local.k3s_network.subnet
    api_endpoint      = "https://${local.k3s_server_ips[local.server_nodes[0]]}:6443"
    database_endpoint = "postgres://k3s:***@${var.postgres_ip}:5432/k3s"
  }
}

# Connection Commands
output "useful_commands" {
  description = "Useful commands for managing the cluster"
  value = {
    ssh_first_server = "ssh ${var.k3s_username}@${local.k3s_server_ips[local.server_nodes[0]]}"
    ssh_database     = "ssh ${var.k3s_username}@${var.postgres_ip}"
    kubectl_config   = "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
    get_nodes        = "kubectl get nodes -o wide"
    cluster_info     = "kubectl cluster-info"
  }
}

# Network Configuration
output "network_config" {
  description = "Network configuration details"
  value = {
    vlan_id      = local.k3s_network.vlan_id
    subnet       = local.k3s_network.subnet
    gateway      = local.k3s_network.gateway
    dns_servers  = ["10.0.0.10", "10.0.0.11"]
    domain       = "homelab.local"
    cluster_cidr = "10.42.0.0/16"
    service_cidr = "10.43.0.0/16"
  }
}
