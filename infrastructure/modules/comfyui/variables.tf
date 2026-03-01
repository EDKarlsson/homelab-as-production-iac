# ComfyUI VM Template
variable "template_vm_id" {
  type        = number
  description = "VM ID of the template to clone for the ComfyUI VM"
  default     = 9000
}

variable "template_node_name" {
  type        = string
  description = "Proxmox node that hosts the VM template for cloning"
  default     = "node-02"
}

# ComfyUI VM Placement
variable "node_name" {
  type        = string
  description = "Proxmox node where the ComfyUI VM will run"
  default     = "node-05"
}

variable "vm_id" {
  type        = number
  description = "VM ID for the ComfyUI VM"
  default     = 530
}

variable "vm_name" {
  type        = string
  description = "Name for the ComfyUI VM"
  default     = "homelab-comfyui-vm"
}

# Storage
variable "datastore_id" {
  type        = string
  description = "Proxmox datastore for VM disks"
  default     = "local-lvm"
}

variable "snippet_datastore_id" {
  type        = string
  description = "Proxmox datastore for cloud-config snippets"
  default     = "Proxmox_NAS"
}

variable "disk_size_gb" {
  type        = number
  description = "OS/data disk size in GB for the ComfyUI VM"
  default     = 120
}

# VM Sizing
variable "cpu_cores" {
  type        = number
  description = "CPU cores for the ComfyUI VM"
  default     = 8
}

variable "memory_mb" {
  type        = number
  description = "Memory in MB for the ComfyUI VM"
  default     = 16384
}

variable "machine_type" {
  type        = string
  description = "Optional VM machine type override (empty = auto)"
  default     = ""
}

variable "bios_type" {
  type        = string
  description = "Optional VM BIOS type override (empty = auto)"
  default     = ""
}

# Network
variable "ip_address" {
  type        = string
  description = "Static IPv4 address for the ComfyUI VM"
  default     = "10.0.0.53"
}

variable "gateway" {
  type        = string
  description = "Default gateway for the ComfyUI VM"
  default     = "10.0.0.1"
}

variable "dns_servers" {
  type        = list(string)
  description = "DNS servers for the ComfyUI VM"
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "domain" {
  type        = string
  description = "DNS domain for the ComfyUI VM"
  default     = "homelab.local"
}

# Access
variable "vm_username" {
  type        = string
  description = "Default username for VM initialization"
  default     = "comfyadmin"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for VM access"
  sensitive   = true
}

# ComfyUI Runtime
variable "comfyui_port" {
  type        = number
  description = "TCP port exposed by ComfyUI"
  default     = 8188
}

variable "comfyui_source_ref" {
  type        = string
  description = "ComfyUI git ref used for docker build (tag/commit/branch)"
  default     = "master"
}

variable "comfyui_base_image" {
  type        = string
  description = "Generic base image used for ComfyUI build (must not be a ComfyUI image)"
  default     = "python:3.11-slim"
}

# Optional NVIDIA GPU passthrough
variable "gpu_passthrough_enabled" {
  type        = bool
  description = "Enable host PCI passthrough for a physical GPU"
  default     = false
}

variable "gpu_pci_id" {
  type        = string
  description = "Primary GPU PCI ID (example: 0000:01:00 or 0000:01:00.0)"
  default     = ""
}

variable "gpu_audio_pci_id" {
  type        = string
  description = "Optional GPU HDMI audio PCI ID (example: 0000:01:00.1)"
  default     = ""
}

variable "gpu_pcie" {
  type        = bool
  description = "Use PCIe for passthrough device (requires q35 machine type)"
  default     = true
}

variable "gpu_rombar" {
  type        = bool
  description = "Expose option ROM to the VM for passthrough device"
  default     = true
}

variable "gpu_xvga" {
  type        = bool
  description = "Mark passthrough GPU as primary VGA device"
  default     = false
}

# VM lifecycle control
variable "on_boot" {
  type        = bool
  description = "Whether Proxmox should start this VM automatically on host boot"
  default     = true
}

variable "started" {
  type        = bool
  description = "Whether Terraform should start the VM on apply (false = manage config only)"
  default     = true
}
