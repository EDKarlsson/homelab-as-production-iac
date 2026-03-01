output "container_id" {
  description = "ComfyUI LXC container ID"
  value       = proxmox_virtual_environment_container.comfyui.id
}

output "hostname" {
  description = "ComfyUI LXC hostname"
  value       = proxmox_virtual_environment_container.comfyui.initialization[0].hostname
}

output "node_name" {
  description = "Proxmox node running the ComfyUI LXC"
  value       = proxmox_virtual_environment_container.comfyui.node_name
}

output "ip_address" {
  description = "ComfyUI LXC IPv4 address"
  value       = var.ip_address
}

output "ssh_command" {
  description = "SSH command for ComfyUI LXC"
  value       = "ssh root@${var.ip_address}"
}

output "gpu_passthrough" {
  description = "GPU passthrough enabled"
  value       = var.gpu_passthrough_enabled
}
