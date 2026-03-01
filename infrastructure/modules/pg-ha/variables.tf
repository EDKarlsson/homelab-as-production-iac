# PostgreSQL HA Module Variables

# --- VM Template ---
variable "template_vm_id" {
  type        = number
  description = "VM ID of the template to clone for PostgreSQL nodes"
  default     = 9000
}

variable "template_node_name" {
  type        = string
  description = "Proxmox node that hosts the VM template for cloning"
  default     = "node-02"
}

# --- Storage ---
variable "datastore_id" {
  type        = string
  description = "Proxmox datastore for VM disks (must support images content type)"
  default     = "local-lvm"
}

variable "snippet_datastore_id" {
  type        = string
  description = "Proxmox datastore for cloud-config snippets (must support snippets content type)"
  default     = "Proxmox_NAS"
}

# --- PostgreSQL Credentials ---
variable "postgres_password" {
  type        = string
  description = "PostgreSQL superuser and application database password"
  sensitive   = true
}

variable "replication_password" {
  type        = string
  description = "Password for the PostgreSQL replication user"
  sensitive   = true
}

# --- VM Access ---
variable "vm_username" {
  type        = string
  description = "Default username for VM initialization"
  default     = "k3sadmin"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for VM access"
  sensitive   = true
}

# --- Network ---
variable "gateway" {
  type        = string
  description = "Default gateway for PostgreSQL VMs"
  default     = "10.0.0.1"
}

variable "vip" {
  type        = string
  description = "Keepalived virtual IP address for PostgreSQL failover"
  default     = "10.0.0.44"
}
