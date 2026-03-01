output "vm_id" {
  description = "ComfyUI VM ID"
  value       = proxmox_virtual_environment_vm.comfyui.vm_id
}

output "vm_name" {
  description = "ComfyUI VM name"
  value       = proxmox_virtual_environment_vm.comfyui.name
}

output "node_name" {
  description = "Proxmox node running the ComfyUI VM"
  value       = proxmox_virtual_environment_vm.comfyui.node_name
}

output "ip_address" {
  description = "ComfyUI VM IPv4 address"
  value       = var.ip_address
}

output "url" {
  description = "ComfyUI URL"
  value       = "http://${var.ip_address}:${var.comfyui_port}"
}

output "ssh_command" {
  description = "SSH command for ComfyUI VM"
  value       = "ssh ${var.vm_username}@${var.ip_address}"
}

output "gpu_passthrough" {
  description = "GPU passthrough configuration"
  value = {
    enabled      = var.gpu_passthrough_enabled
    gpu_pci_id   = var.gpu_pci_id
    audio_pci_id = var.gpu_audio_pci_id
  }
}
