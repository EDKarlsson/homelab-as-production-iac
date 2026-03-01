# --- Values sourced from 1Password ---
output "pve_endpoint" {
  description = "Proxmox VE API Endpoint (from 1Password)"
  value       = data.onepassword_item.proxmox_tf.section_map["credentials"].field_map["endpoint"].value
  sensitive   = true
}

# --- Proxmox defaults ---
output "pve_node_name" {
  description = "Proxmox VE API Node Name"
  value       = var.proxmox_ve_node_name
}

output "pve_datastore_id" {
  description = "Proxmox VE Datastore ID for VM Disks"
  value       = var.proxmox_ve_datastore_id
}

# --- ComfyUI LXC (disabled — module commented out in main.tf) ---
# output "comfyui_lxc" {
#   description = "ComfyUI LXC deployment details"
#   value = {
#     container_id    = module.comfyui_lxc.container_id
#     hostname        = module.comfyui_lxc.hostname
#     node_name       = module.comfyui_lxc.node_name
#     ip_address      = module.comfyui_lxc.ip_address
#     ssh_command     = module.comfyui_lxc.ssh_command
#     gpu_passthrough = module.comfyui_lxc.gpu_passthrough
#   }
# }
