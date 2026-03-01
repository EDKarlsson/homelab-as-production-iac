# Terraform Module Audit Report

Automated audit of all Terraform modules in `infrastructure/modules/` against bpg/proxmox provider v0.95.0.

**Date:** 2026-02-15
**Scope:** `infrastructure/` (all modules)
**Provider:** bpg/proxmox v0.95.0 (locked in `.terraform.lock.hcl`)

---

## Summary

| Severity                                    | Count | Resolved |
|---------------------------------------------|-------|----------|
| **ERROR** (blocks validate/apply)           | 9     | 9        |
| **WARNING** (may cause unexpected behavior) | 8     | 8        |
| **INFO** (style/convention)                 | 5     | 5        |

**All issues resolved as of 2026-02-15.**

---

## Module: `modules/k3s/`

Files: `k3s-cluster.tf`, `k3s-cloud-configs.tf`, `variables.tf`, `outputs.tf`

This module defines the full k3s cluster (5 servers, 5 agents, 1 PostgreSQL VM). It is **not referenced
from `main.tf`** yet — none of these resources are active.

### ~~Issue #1~~ — RESOLVED: `user_account` and `user_data_file_id` conflict

**Files:** `k3s-cluster.tf` lines 99-104, 172-177, 255-260

All three VM resources specify both `user_account { ... }` and `user_data_file_id` inside the same
`initialization` block. In bpg/proxmox v0.95.0, these are **mutually exclusive** — `user_account`
generates a cloud-init `user` section, while `user_data_file_id` provides a complete cloud-config
that already defines users. One overwrites the other.

**Fix:** Remove the `user_account` block from all three resources. The cloud-config templates
(`k3s-server.yml.tpl`, `k3s-agent.yml.tpl`, `postgresql.yml.tpl`) already define users with SSH keys.

**Docs:**
- [initialization block](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#initialization)
- [GitHub issue context](https://github.com/bpg/terraform-provider-proxmox/issues/1131)

---

### ~~Issue #2~~ — RESOLVED: `file_id = null` on clone disks

**Files:** `k3s-cluster.tf` lines 78, 151, 223, 234

Setting `file_id = null` explicitly on disk blocks for cloned VMs is unnecessary. For clones, the disk
comes from the source template. Explicitly setting `file_id = null` can confuse the provider and may
trigger drift detection or plan errors.

**Fix:** Remove `file_id = null` from all disk blocks on cloned VMs.

---

### ~~Issue #3~~ — RESOLVED: Missing `clone.node_name` for cross-node cloning

**Files:** `k3s-cluster.tf` lines 50-53, 123-126, 194-197

VMs are deployed to 5 different nodes (`node_name = each.key`), but `clone` blocks do not specify
`node_name` to indicate which node holds the source template VM (ID 9000). Without this, the provider
assumes the template is on the **same** node as the target. If the template only exists on one node,
cloning to the other 4 will fail.

**Fix:** Add `node_name = "<template-node>"` inside each `clone` block:

```hcl
clone {
  vm_id     = var.k3s_template_vm_id
  node_name = "node-02"  # wherever template 9000 lives
  full      = true
}
```

**Docs:**
- [clone block](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#clone)

---

### ~~Issue #4~~ — RESOLVED: Missing `clone.datastore_id` for cross-node cloning

**Files:** Same as Issue #3

When cloning across nodes, the provider needs `datastore_id` in the `clone` block to place the
cloned disk on the target node's storage. Without it, the provider attempts to use the source
datastore name, which may not exist on the target.

**Fix:** Add `datastore_id = "local-lvm"` inside each `clone` block.

**Docs:**
- [clone block](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#clone)
- [GitHub issue #2225](https://github.com/bpg/terraform-provider-proxmox/issues/2225)

---

### ~~Issue #5~~ — RESOLVED: Missing variable declarations

**File:** `variables.tf`

The module only declares 4 variables (`k3s_template_vm_id`, `k3s_version`, `k3s_cluster_token`,
`postgres_password`), but references 3 additional undeclared variables:

| Variable | Used in |
|----------|---------|
| `var.vm_username` | k3s-cluster.tf, k3s-cloud-configs.tf, outputs.tf |
| `var.ssh_public_key` | k3s-cluster.tf, k3s-cloud-configs.tf |
| `var.virtual_environment_datastore_id` | k3s-cluster.tf, k3s-cloud-configs.tf |

**Fix:** Add these to `variables.tf`:

```hcl
variable "vm_username" {
  type        = string
  description = "Default username for VM initialization"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for VM access"
  sensitive   = true
}

variable "virtual_environment_datastore_id" {
  type        = string
  description = "Datastore for VM disks and snippets"
}
```

---

### ~~Issue #6~~ — RESOLVED: Missing `required_providers` block

**File:** No `providers.tf` or `terraform` block exists in the module.

The k3s module uses `proxmox_virtual_environment_vm` and `proxmox_virtual_environment_file` but has
no `required_providers` declaration. Without it, Terraform defaults to looking for `hashicorp/proxmox`.

**Fix:** Create `modules/k3s/providers.tf`:

```hcl
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.95.0"
    }
  }
}
```

**Docs:**
- [Provider requirements in modules](https://developer.hashicorp.com/terraform/language/providers/requirements)
- See also: [Terraform Provider Setup guide](./terraform-provider-setup.md)

---

### ~~Issue #7~~ — RESOLVED: Cloud-config template path is broken

**File:** `k3s-cloud-configs.tf` lines 12, 38, 58

`templatefile()` calls reference `"${path.module}/cloud-configs/k3s-server.yml.tpl"`. Since
`path.module` for the k3s module is `infrastructure/modules/k3s/`, this resolves to
`infrastructure/modules/k3s/cloud-configs/`. That directory **does not exist**. The actual templates
are at `infrastructure/modules/cloud-configs/` (a sibling directory).

**Fix:** Either:
1. **(Preferred)** Move the templates into `modules/k3s/cloud-configs/`
2. Change paths to `"${path.module}/../cloud-configs/..."` (fragile, not recommended)

---

### ~~Issue #8~~ — RESOLVED: `cluster-init` conflicts with PostgreSQL datastore

**File:** `modules/cloud-configs/k3s-server.yml.tpl` lines 76-79

The K3s server config contains both:
```yaml
cluster-init: ${cluster_init}
datastore-endpoint: postgres://k3s:${postgres_password}@${postgres_ip}:5432/k3s
```

`cluster-init` is **only for embedded etcd**. K3s cannot use both embedded etcd and an external
PostgreSQL datastore simultaneously. When using PostgreSQL, `cluster-init` should not be set.

Additionally, `server: https://${first_server_ip}:6443` is present for all nodes including the first
server, which is contradictory when `cluster_init = true`.

**Fix:** Remove the `cluster-init` line entirely. With an external PostgreSQL datastore, all servers
simply connect to the same `--datastore-endpoint` and use the same `--token`. No `--server` flag
is needed for server nodes (only for agents).

**Docs:**
- [K3s Cluster Datastore](https://docs.k3s.io/datastore)
- [K3s HA with External DB](https://docs.k3s.io/datastore/ha)

---

### ~~Issue #9~~ — RESOLVED: Unnecessary `mac_address = null`

**Files:** `k3s-cluster.tf` lines 74, 147, 216

`mac_address = null` is the default and adds visual noise.

**Fix:** Remove from all `network_device` blocks.

---

### ~~Issue #10~~ — RESOLVED: `file_format = "raw"` may conflict with template format

**Files:** `k3s-cluster.tf` lines 81, 154, 225, 236

Explicitly setting `file_format = "raw"` on cloned disks may cause conversion overhead if the
template uses qcow2. Usually best to omit and let the provider inherit the source format.

**Fix:** Remove `file_format` from clone disk blocks, or verify the template uses raw format.

---

## ~~Module: `modules/vm-clone/`~~ — DELETED

**Deleted 2026-02-15.** This module was unused example/reference code. Issues #11-#15 resolved by deletion.

### ~~Issue #11~~ — RESOLVED: Missing `required_providers` block

Uses `proxmox_virtual_environment_vm`, `proxmox_virtual_environment_file`,
`proxmox_virtual_environment_download_file`, and `data.local_file` but has no `required_providers`.

**Fix:** Add `providers.tf` with both `bpg/proxmox` and `hashicorp/local`.

---

### ~~Issue #12~~ — RESOLVED: No disk block on clone VM

**File:** `clone.tf` lines 1-32

The clone resource has no `disk` block at all. Omitting it entirely on a clone risks triggering
provider issue #2225 (provider doesn't know where to put the disk on cross-node clones).

**Fix:** Add an explicit `disk` block with `datastore_id` and `interface` matching the template.

**Docs:** [GitHub issue #2225](https://github.com/bpg/terraform-provider-proxmox/issues/2225)

---

### ~~Issue #13~~ — RESOLVED: SSH key read from relative path

**File:** `cloud-config.tf` line 2

```hcl
data "local_file" "ssh_public_key" {
  filename = "./id_rsa.pub"
}
```

`./` resolves relative to the module directory (`modules/vm-clone/`). The file likely doesn't exist
there, and hardcoding key paths is not a secure practice.

**Fix:** Use a variable to pass the SSH key instead.

---

### ~~Issue #14~~ — RESOLVED: 4 unused variables

**File:** `variables.tf`

`virtual_environment_endpoint`, `virtual_environment_password`, `virtual_environment_username`,
`virtual_environment_token` are declared but never referenced. These appear to be leftovers from
when this module contained its own provider block.

**Fix:** Remove unused variables.

---

### ~~Issue #15~~ — RESOLVED: Empty `output.tf`

**File:** `output.tf`

The file exists but is empty. The actual output (`vm_ipv4_address`) is defined inline in `clone.tf`.

**Fix:** Move the output to `output.tf` or remove the empty file.

---

## ~~Module: `modules/vm/`~~ — DELETED

**Deleted 2026-02-15.** This module was unused example/reference code. Issues #16-#19 resolved by deletion.

### ~~Issue #16~~ — RESOLVED: References undefined resource

**File:** `main.tf` lines 3, 4, 13, 25

References `proxmox_virtual_environment_vm.example` in `depends_on` and `.vm_id` attributes, but
no such resource is defined anywhere. This module will not validate.

**Fix:** This appears to be example/reference code copied from provider docs. Either complete it
or remove it if not in use.

---

### ~~Issue #17~~ — RESOLVED: Missing `required_providers` block

Same pattern as other modules — no `terraform { required_providers { } }` block.

---

### ~~Issue #18~~ — RESOLVED: Empty `output.tf`

Same pattern as vm-clone module.

---

### ~~Issue #19~~ — RESOLVED: Unused variables

**File:** `variables.tf`

`vm_username` and `vm_ssh_public_key` are declared but never referenced in `main.tf`.

---

## Module: `modules/pve/`

Files: `main.tf`, `output.tf`, `providers.tf`

### Issue #20 — INFO: Only module with correct `required_providers`

**File:** `providers.tf` correctly declares `bpg/proxmox >= 0.95.0`.

**No errors found.** This module is a simple `data "proxmox_virtual_environment_nodes"` call with outputs.

---

## Root Configuration

### Issue #21 — WARNING: k3s module not referenced from `main.tf`

`main.tf` only calls `module "pve"`. The k3s module exists but is not wired up. None of the k3s
resources will be created until a `module "k3s"` call is added.

---

### ~~Issue #22~~ — RESOLVED: `modules/vm-clone/` and `modules/vm/` deleted

These modules were reference/example code from provider documentation. **Deleted 2026-02-15.**

---

### ~~Issue #23~~ — RESOLVED: SSH username fixed to `"root"`

**File:** `main.tf` lines 18-21

```hcl
ssh {
  agent    = true
  username = var.proxmox_ve_username
}
```

`var.proxmox_ve_username` is `terraform@pve!provider` (the API token user). The SSH `username` needs
to be the **OS-level** SSH user (e.g., `root`), not the PVE API user which includes realm and token
suffixes. Using `terraform@pve!provider` as an SSH username will fail.

**Fix:** Use the OS username directly:

```hcl
ssh {
  agent    = true
  username = "root"
}
```

**Docs:**
- [Provider SSH configuration](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs#ssh)

---

## Priority Fix Order — All Resolved

1. ~~**Issue #7** — Move cloud-config templates to correct path~~ ✓
2. ~~**Issue #5** — Add missing variable declarations~~ ✓
3. ~~**Issue #1** — Remove `user_account` blocks~~ ✓
4. ~~**Issues #3 & #4** — Add `clone.node_name` and `clone.datastore_id`~~ ✓
5. ~~**Issue #2** — Remove `file_id = null` from clone disks~~ ✓
6. ~~**Issue #8** — Remove `cluster-init` from cloud-config~~ ✓
7. ~~**Issue #6** — Add `required_providers` to k3s module~~ ✓
8. ~~**Issue #23** — Fix SSH username in provider config~~ ✓ (fixed in 1Password integration PR)
9. **Issue #21** — Wire up `module "k3s"` in `main.tf` (when ready to deploy)

---

## Cluster Environment Data

Gathered via Proxmox API on 2026-02-15:

### Cluster Status

| Property | Value |
|----------|-------|
| Cluster name | `valhalla` |
| Nodes | 5 (all online, quorate) |
| PVE version | 9.1.5 (all nodes identical) |

### Node IPs

| Node | IP |
|------|-----|
| node-02 | 10.0.0.10 |
| node-03 | 10.0.0.11 |
| node-04 | 10.0.0.12 |
| node-01 | 10.0.0.13 |
| node-05 | 10.0.0.14 |

### Network

All nodes have `vmbr0` bridge on 10.0.0.0/24. No VLAN interfaces at the host level (VM VLAN
tags are applied on the bridge).

### Storage (local-lvm available space)

| Node | Available |
|------|-----------|
| node-01 | 816 GB |
| node-02 | 348 GB |
| node-03 | 816 GB |
| node-04 | 816 GB |
| node-05 | 1,710 GB |
| **Proxmox_NAS** (NFS, shared) | **13,326 GB** |
