# Terraform Provider Setup (bpg/proxmox)

Reference notes for configuring the bpg/proxmox Terraform provider in a multi-module project.

## Provider declaration
- Declare the provider **in the root module** (`main.tf`), not in child modules
- Child modules inherit providers from the root automatically
- Only use explicit `providers = {}` on a module block when using provider aliases

## Child modules need `required_providers`
Without a `required_providers` block, Terraform assumes `hashicorp/<name>`. Every child module using a non-hashicorp provider must declare the source:

```hcl
# modules/pve/providers.tf
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.95.0"
    }
  }
}
```

No `provider` block in the child — just the source mapping.

## Passing variables to submodules
1. Declare `variable` blocks in the child module (`modules/pve/variables.tf`)
2. Pass values on the `module` block in the root:

```hcl
module "pve" {
  source       = "./modules/pve"
  node_name    = var.proxmox_ve_node_name
  datastore_id = var.proxmox_ve_datastore_id
}
```

## 1Password provider (future integration)

The `1Password/onepassword` provider is already configured in `main.tf` alongside `bpg/proxmox`.
It connects to the 1Password Connect server to read secrets at plan/apply time:

```hcl
# infrastructure/main.tf (existing)
provider "onepassword" {
  connect_token = var.op_connect_token    # env: TF_VAR_op_connect_token
  connect_url   = var.op_connect_host     # env: TF_VAR_op_connect_host
}
```

Child modules can use `onepassword_item` data sources to read credentials from 1Password
instead of receiving them as variables. See
[Guide 6: 1Password Secrets Management](./1password-secrets-management.md#part-3-terraform-integration)
for full details on reading secrets, eliminating `TF_VAR_*` environment variables, and creating
managed items.

**Docs:**
- Provider registry: https://registry.terraform.io/providers/1Password/onepassword/latest/docs
- Provider GitHub: https://github.com/1Password/terraform-provider-onepassword

## Outputting values from submodules
1. Declare `output` blocks in the child module (`modules/pve/output.tf`)
2. Reference from root via `module.<name>.<output_name>`:

```hcl
output "pve_nodes" {
  value = module.pve.data_proxmox_virtual_environment_nodes
}
```
