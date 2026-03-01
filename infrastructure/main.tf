terraform {
  required_version = ">= 1.5"
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 3.2"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.95.0" # x-release-please-version
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

# --- 1Password provider (Connect mode) ---
# Authenticates via self-hosted Connect server (unlimited reads, no rate limits).
# Requires: TF_VAR_op_connect_token + TF_VAR_op_connect_host
# Docs: https://registry.terraform.io/providers/1Password/onepassword/latest/docs
provider "onepassword" {
  connect_url   = var.op_connect_host
  connect_token = var.op_connect_token
}

# --- 1Password data sources ---
data "onepassword_vault" "homelab" {
  name = "Homelab"
}

data "onepassword_item" "pve_root" {
  vault = data.onepassword_vault.homelab.uuid
  title = "ssh-homelab-pve-root-2025"
}

data "onepassword_item" "proxmox_tf" {
  vault = data.onepassword_vault.homelab.uuid
  title = "PVE_Terraform"
}

data "onepassword_item" "k3s_cluster" {
  vault = data.onepassword_vault.homelab.uuid
  title = "homelab-k3s-cluster"
}

# --- Proxmox provider (credentials from 1Password) ---
provider "proxmox" {
  endpoint = data.onepassword_item.proxmox_tf.section_map["credentials"].field_map["endpoint"].value
  username = "root@pam"
  password = data.onepassword_item.proxmox_tf.section_map["credentials"].field_map["password"].value
  insecure = true
  ssh {
    agent       = true
    username    = "root"
    private_key = data.onepassword_item.pve_root.private_key
  }
}

module "pve" {
  source = "./modules/pve"
}

module "k3s" {
  source            = "./modules/k3s"
  k3s_cluster_token = data.onepassword_item.k3s_cluster.section_map["cluster"].field_map["server-token"].value
  postgres_password = data.onepassword_item.k3s_cluster.section_map["database"].field_map["password"].value
  ssh_public_key    = data.onepassword_item.k3s_cluster.public_key
  # 10.0.0.202: MetalLB LoadBalancer IP allocated to nexus-lb service (service-lb.yaml).
  # Must be HTTP (not HTTPS) — cloud-init runs before the homelab CA cert is trusted.
  # Cannot use the ingress-nginx VIP (10.0.0.201) — that route goes through OAuth2 Proxy.
  nexus_apt_mirror_url = "http://10.0.0.202:8081"
}

# --- PostgreSQL HA (2 VMs + keepalived VIP failover) ---
module "pg_ha" {
  source               = "./modules/pg-ha"
  postgres_password    = data.onepassword_item.k3s_cluster.section_map["database"].field_map["password"].value
  replication_password = data.onepassword_item.k3s_cluster.section_map["database"].field_map["replication-password"].value
  ssh_public_key       = data.onepassword_item.k3s_cluster.public_key
}

# --- State migration: PostgreSQL VM moved from k3s module to pg-ha module ---
moved {
  from = module.k3s.proxmox_virtual_environment_vm.postgres_db
  to   = module.pg_ha.proxmox_virtual_environment_vm.postgres["node-01"]
}

moved {
  from = module.k3s.proxmox_virtual_environment_file.postgres_cloud_config
  to   = module.pg_ha.proxmox_virtual_environment_file.pg_cloud_config["node-01"]
}

# --- 1Password Connect HA (2 LXC containers + keepalived VIP) ---
data "onepassword_item" "op_connect_server" {
  vault = data.onepassword_vault.homelab.uuid
  title = "1Password-Connect-Server"
}

module "op_connect" {
  source             = "./modules/op-connect"
  op_credentials_b64 = data.onepassword_item.op_connect_server.section_map["server"].field_map["credentials-b64"].value
  ssh_public_key     = data.onepassword_item.pve_root.public_key
  ssh_private_key    = data.onepassword_item.pve_root.private_key
}

# --- ComfyUI LXC (DISABLED — gpu-workstation repurposed as standalone workstation) ---
#
# History: gpu-workstation (ASRock X299 Taichi, i7-7820X, RTX 3060) was a Proxmox cluster
# node. Two approaches were tried for GPU compute:
#
#   1. KVM VM + VFIO passthrough: abandoned — RTX 3060/Ampere + X299/Skylake-X PCIe
#      bus reset incompatibility caused host kernel panics during guest NVIDIA driver init.
#
#   2. Privileged LXC + host NVIDIA driver bind-mount: implemented (modules/comfyui-lxc),
#      NVIDIA 580.126.18 installed and working, devices visible in container — but
#      pct exec + privileged LXC + cgroup2 on kernel 6.17 / X299 caused repeatable
#      host crashes during apt-get workloads inside the container. Root cause unknown.
#      BIOS update P1.70 → P2.50 and vendor-reset removal did not resolve the crashes.
#
# Decision: gpu-workstation removed from Proxmox cluster, reinstalled as standalone Ubuntu
# workstation. ComfyUI runs natively (no Docker/LXC) with direct NVIDIA driver access.
#
# The modules/comfyui-lxc module is retained for documentation and potential reuse
# on more stable hardware.
#
# TODO (before re-enabling): remove stale Terraform state for this module:
#   terraform state rm 'module.comfyui_lxc.proxmox_virtual_environment_container.comfyui'
#   terraform state rm 'module.comfyui_lxc.null_resource.nvidia_lxc_passthrough[0]'
#
# module "comfyui_lxc" {
#   source = "./modules/comfyui-lxc"
#
#   ssh_public_key  = data.onepassword_item.k3s_cluster.public_key
#   ssh_private_key = data.onepassword_item.pve_root.private_key
#
#   gpu_passthrough_enabled = true
#   on_boot                 = false
#   started                 = false
# }
