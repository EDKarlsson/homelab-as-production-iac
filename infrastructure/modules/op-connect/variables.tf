# 1Password Connect Credentials
variable "op_credentials_b64" {
  type        = string
  description = "Base64-encoded 1password-credentials.json file content"
  sensitive   = true
}

# SSH Keys
variable "ssh_public_key" {
  type        = string
  description = "SSH public key injected into LXC containers for root access"
}

variable "ssh_private_key" {
  type        = string
  description = "SSH private key for Terraform provisioner connections to LXC containers"
  sensitive   = true
}

# LXC Container Sizing
variable "lxc_template_storage" {
  type        = string
  description = "Proxmox storage for LXC templates (must support vztmpl content type)"
  default     = "local"
}

variable "lxc_template_url" {
  type        = string
  description = "URL for the Ubuntu LXC template (verify with: pveam available --section system | grep ubuntu-24)"
  default     = "http://download.proxmox.com/images/system/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

variable "lxc_disk_storage" {
  type        = string
  description = "Proxmox storage for LXC rootfs disks"
  default     = "local-lvm"
}

variable "lxc_disk_size" {
  type        = number
  description = "LXC rootfs disk size in GB"
  default     = 8
}

variable "lxc_memory" {
  type        = number
  description = "LXC container memory in MB (Docker + connect-api + connect-sync + keepalived)"
  default     = 512
}

variable "lxc_cpu_cores" {
  type        = number
  description = "Number of CPU cores per LXC container"
  default     = 1
}

# Network
variable "gateway" {
  type        = string
  description = "Default gateway for LXC containers"
  default     = "10.0.0.1"
}

variable "vip" {
  type        = string
  description = "Keepalived virtual IP address for Connect failover"
  default     = "10.0.0.72"
}
