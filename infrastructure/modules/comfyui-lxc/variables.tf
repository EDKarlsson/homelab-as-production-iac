# ComfyUI LXC Placement
variable "node_name" {
  type        = string
  description = "Proxmox node where the ComfyUI LXC will run"
  default     = "gpu-workstation"
}

variable "node_host" {
  type        = string
  description = "IP address of the Proxmox node (for SSH connection used by null_resource NVIDIA config)"
  default     = "10.0.0.15"
}

variable "vm_id" {
  type        = number
  description = "Container ID for the ComfyUI LXC"
  default     = 530
}

variable "hostname" {
  type        = string
  description = "Hostname for the ComfyUI LXC"
  default     = "homelab-comfyui-lxc"
}

# Template
variable "template_file_id" {
  type        = string
  description = "LXC template file ID on the Proxmox node (must be pre-downloaded via pveam)"
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

# Storage
variable "datastore_id" {
  type        = string
  description = "Proxmox datastore for container root disk"
  default     = "local-lvm"
}

variable "disk_size_gb" {
  type        = number
  description = "Root disk size in GB"
  default     = 120
}

# Sizing
variable "cpu_cores" {
  type        = number
  description = "CPU cores for the ComfyUI LXC"
  default     = 8
}

variable "memory_mb" {
  type        = number
  description = "Memory in MB for the ComfyUI LXC"
  default     = 16384
}

# Network
variable "ip_address" {
  type        = string
  description = "Static IPv4 address for the ComfyUI LXC"
  default     = "10.0.0.53"
}

variable "gateway" {
  type        = string
  description = "Default gateway for the ComfyUI LXC"
  default     = "10.0.0.1"
}

variable "dns_servers" {
  type        = list(string)
  description = "DNS servers for the ComfyUI LXC"
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "domain" {
  type        = string
  description = "DNS domain for the ComfyUI LXC"
  default     = "homelab.local"
}

# Access
variable "ssh_public_key" {
  type        = string
  description = "SSH public key injected into root's authorized_keys"
  sensitive   = true
}

variable "ssh_private_key" {
  type        = string
  description = "SSH private key for the Proxmox host root user (used by null_resource NVIDIA config)"
  sensitive   = true
}

# NVIDIA GPU passthrough (host driver → LXC device bind-mount)
variable "gpu_passthrough_enabled" {
  type        = bool
  description = "Bind-mount host NVIDIA device nodes into the LXC container"
  default     = false
}

# Lifecycle control
variable "on_boot" {
  type        = bool
  description = "Whether Proxmox should start this LXC automatically on host boot (maps to start_on_boot)"
  default     = false
}

variable "started" {
  type        = bool
  description = "Whether Terraform should start the LXC on apply"
  default     = false
}
