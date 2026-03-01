# K3s Cluster Variables
variable "k3s_template_vm_id" {
  type        = number
  description = "VM ID of the template to clone for K3s nodes"
  default     = 9000
}

variable "k3s_template_node_name" {
  type        = string
  description = "Proxmox node that hosts the VM template for cloning"
  default     = "node-02"
}

# K3s Configuration
variable "k3s_version" {
  type        = string
  description = "K3s version to install"
  default     = "v1.32.12+k3s1"
}

variable "k3s_cluster_token" {
  type        = string
  description = "K3s cluster token for node joining"
  sensitive   = true
}

# VM Configuration
variable "k3s_username" {
  type        = string
  description = "Default username for K3s VM initialization"
  default     = "k3sadmin"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for VM access"
  sensitive   = true
}

variable "virtual_environment_datastore_id" {
  type        = string
  description = "Proxmox datastore for VM disks and cloud-config snippets"
  default     = "local-lvm"
}

# PostgreSQL Configuration (VM managed by pg-ha module; K3s servers need IP + password for datastore-endpoint)
variable "postgres_password" {
  type        = string
  description = "PostgreSQL database password (used in K3s server cloud-config for datastore-endpoint)"
  sensitive   = true
}

variable "postgres_ip" {
  type        = string
  description = "PostgreSQL server IP for K3s datastore-endpoint (use VIP for HA)"
  default     = "10.0.0.44"
}

variable "nexus_apt_mirror_url" {
  type        = string
  description = "Nexus APT proxy base URL reachable from VMs during cloud-init (requires Nexus exposed without auth, e.g. NodePort or dedicated ingress)"
  default     = ""
}

variable "virtual_environment_snippet_datastore_id" {
  type        = string
  description = "Proxmox datastore for cloud-config snippets"
  default     = "Proxmox_NAS"
}