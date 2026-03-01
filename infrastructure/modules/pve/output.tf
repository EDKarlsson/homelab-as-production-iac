output "data_proxmox_virtual_environment_nodes" {
  value = {
    names     = data.proxmox_virtual_environment_nodes.pve_nodes.names
    cpu_count = data.proxmox_virtual_environment_nodes.pve_nodes.cpu_count
    online    = data.proxmox_virtual_environment_nodes.pve_nodes.online
  }
}