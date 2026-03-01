# VIP — the address all consumers should use
output "connect_url" {
  description = "1Password Connect URL (keepalived VIP)"
  value       = "http://${var.vip}:8080"
}

# Individual instance details
output "instances" {
  description = "Map of node name to instance details (IP, CT ID, role)"
  value = {
    for node, inst in local.instances : node => {
      ip    = inst.ip
      ct_id = inst.ct_id
      state = inst.state
    }
  }
}

# Convenience health check commands
output "health_check_commands" {
  description = "Commands to verify Connect health"
  value = {
    vip = "curl -sf http://${var.vip}:8080/heartbeat"
    nodes = {
      for node, inst in local.instances :
      node => "curl -sf http://${inst.ip}:8080/heartbeat"
    }
  }
}
