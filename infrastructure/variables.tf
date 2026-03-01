# --- 1Password Connect authentication ---
variable "op_connect_token" {
  type        = string
  description = "1Password Connect server token (JWT). Set via TF_VAR_op_connect_token."
  sensitive   = true
}

variable "op_connect_host" {
  type        = string
  description = "1Password Connect server URL. Set via TF_VAR_op_connect_host."
}

# --- Proxmox defaults (non-secret) ---
variable "proxmox_ve_node_name" {
  type        = string
  description = "The node name for the Proxmox Virtual Environment API"
  default     = "node-02"
}

variable "proxmox_ve_datastore_id" {
  type        = string
  description = "Datastore for VM disks"
  default     = "local-lvm"
}
