# VIP — the address all consumers should use
output "vip" {
  description = "PostgreSQL VIP address (keepalived)"
  value       = var.vip
}

output "connection_string" {
  description = "PostgreSQL connection string via VIP (use for K3s datastore)"
  value       = "postgres://k3s:***@${var.vip}:5432/k3s"
}

# Individual instance details
output "instances" {
  description = "Map of node name to instance details (IP, VM ID, role, keepalived state)"
  value = {
    for node, inst in local.instances : node => {
      ip    = inst.ip
      vm_id = inst.vm_id
      role  = inst.role
      state = inst.state
    }
  }
}

# Convenience health check commands
output "health_check_commands" {
  description = "Commands to verify PostgreSQL health"
  value = {
    vip = "pg_isready -h ${var.vip} -p 5432"
    nodes = {
      for node, inst in local.instances :
      node => "pg_isready -h ${inst.ip} -p 5432"
    }
    replication = "ssh ${var.vm_username}@${local.instances["node-01"].ip} \"sudo -u postgres psql -c 'SELECT * FROM pg_stat_replication;'\""
  }
}
