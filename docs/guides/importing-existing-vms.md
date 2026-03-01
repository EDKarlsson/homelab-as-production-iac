# Guide: Importing Existing Proxmox VMs into Terraform

This walkthrough covers how to bring VMs that you already created manually in Proxmox
under Terraform management using the `bpg/proxmox` provider. After completing this guide,
Terraform will track the state of those VMs and you can modify them via code going forward.

## Prerequisites

- Terraform >= 1.5 (for `import` block support)
- `bpg/proxmox` provider configured and `terraform init` completed (see [Terraform Provider Setup](./terraform-provider-setup.md))
- Access to the Proxmox web UI or CLI to look up your existing VM details (VM IDs, node names, etc.)

## Key documentation

| Topic | URL |
|---|---|
| `proxmox_virtual_environment_vm` resource | https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm |
| Terraform `import` block reference | https://developer.hashicorp.com/terraform/language/block/import |
| Terraform import overview | https://developer.hashicorp.com/terraform/language/import |
| Generating config from imports | https://developer.hashicorp.com/terraform/language/import/generating-configuration |
| bpg/proxmox GitHub (issues, source) | https://github.com/bpg/terraform-provider-proxmox |

---

## Step 1: Write skeleton resource blocks

**What you're doing:** Telling Terraform "these resources should exist" by writing `resource`
blocks in HCL. These blocks don't create anything yet — they're just declarations that
Terraform will later bind to real infrastructure via import.

**How to do it:**

For each VM you want to import, create a `resource "proxmox_virtual_environment_vm"` block.
The only **required** attribute is `node_name`, but you should include at minimum the
attributes that identify the VM: `node_name`, `vm_id`, and `name`.

```hcl
# Example: infrastructure/modules/pve/vms.tf  (or wherever you want these to live)

resource "proxmox_virtual_environment_vm" "server1" {
  node_name = "node-02"
  vm_id     = 100
  name      = "my-server-1"
}

resource "proxmox_virtual_environment_vm" "server2" {
  node_name = "node-01"
  vm_id     = 101
  name      = "my-server-2"
}

# ... repeat for all 5 VMs
```

Replace the values above with the real node names, VM IDs, and names from your Proxmox
environment. You can find these in the Proxmox web UI sidebar or by running `qm list`
on each PVE host.

**Why a skeleton?** You don't need to specify every attribute right now. In Step 3, Terraform
will compare your skeleton against the real VM and tell you what's different. You'll
iteratively fill in the details.

> **Tip — `for_each` alternative:** If your VMs follow a pattern, you can use a `for_each`
> on a local map instead of individual resource blocks. This is cleaner for many VMs:
>
> ```hcl
> locals {
>   vms = {
>     server1 = { node = "node-02", id = 100, name = "my-server-1" }
>     server2 = { node = "node-01",    id = 101, name = "my-server-2" }
>     # ...
>   }
> }
>
> resource "proxmox_virtual_environment_vm" "imported" {
>   for_each  = local.vms
>   node_name = each.value.node
>   vm_id     = each.value.id
>   name      = each.value.name
> }
> ```

**Docs:**
- Resource attributes: https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm

---

## Step 2: Add `import` blocks

**What you're doing:** Telling Terraform "this resource block maps to this existing
real-world object." The `import` block connects your HCL resource address (the `to`)
to the ID of the actual VM in Proxmox (the `id`).

**How to do it:**

Create an `imports.tf` file (the name doesn't matter — any `.tf` file works) and add
one `import` block per VM:

```hcl
# infrastructure/modules/pve/imports.tf

import {
  to = proxmox_virtual_environment_vm.server1
  id = "node-02/100"
}

import {
  to = proxmox_virtual_environment_vm.server2
  id = "node-01/101"
}

# ... repeat for all 5 VMs
```

**The import ID format** for the bpg/proxmox provider is:

```
<node_name>/<vm_id>
```

For example, a VM with ID `100` on node `node-02` uses the import ID
`node-02/100`.

> **If using `for_each`** on your resource, the `to` must include the map key:
>
> ```hcl
> import {
>   to = proxmox_virtual_environment_vm.imported["server1"]
>   id = "node-02/100"
> }
> ```
>
> Or use `for_each` on the import block itself:
>
> ```hcl
> import {
>   for_each = local.vms
>   to       = proxmox_virtual_environment_vm.imported[each.key]
>   id       = "${each.value.node}/${each.value.id}"
> }
> ```

**Docs:**
- Import block syntax: https://developer.hashicorp.com/terraform/language/block/import

---

## Step 3: Run `terraform plan` to see drift

**What you're doing:** Asking Terraform to read the real state of each VM from Proxmox
and compare it against your skeleton resource blocks. The plan output shows:

1. Which resources will be **imported** (bound to real infrastructure)
2. What **differences (drift)** exist between your HCL and the actual VM config

**How to do it:**

```bash
cd infrastructure
terraform plan
```

The output will look something like:

```
proxmox_virtual_environment_vm.server1: Preparing import... [id=node-02/100]
proxmox_virtual_environment_vm.server1: Refreshing state... [id=node-02/100]

  # proxmox_virtual_environment_vm.server1 will be imported
  # (config will also be updated in-place after import)
    ~ resource "proxmox_virtual_environment_vm" "server1" {
        + cpu {
            + cores   = 4
            + sockets = 1
            + type    = "x86-64-v2-AES"
          }
        + memory {
            + dedicated = 4096
          }
        ... (many more attributes)
      }
```

Lines with `+` are attributes that exist on the real VM but are missing from your HCL.
Lines with `~` are attributes where your HCL value differs from reality. Lines with `-`
are attributes in your HCL that don't exist on the real VM.

**Important:** At this stage, `terraform plan` does NOT modify your state. It is safe to
run repeatedly. Nothing changes until you `terraform apply`.

> **Shortcut — auto-generate config:** Instead of writing skeletons by hand, you can let
> Terraform generate the resource blocks for you:
>
> ```bash
> terraform plan -generate-config-out=generated.tf
> ```
>
> This writes a `generated.tf` file with Terraform's best guess at the full resource
> configuration. You then review and refine it. The file must not already exist.
> **Note:** This is experimental. The output often needs cleanup (removing read-only
> computed attributes, fixing formatting, replacing hardcoded values with variables).
>
> Docs: https://developer.hashicorp.com/terraform/language/import/generating-configuration

---

## Step 4: Adjust HCL to match actual state

**What you're doing:** Filling in your resource blocks so they accurately describe the
VMs as they exist today. The goal is to get `terraform plan` to show **no changes**
beyond the import itself.

**How to do it:**

Look at the plan output from Step 3 and add the missing attributes to your resource blocks.
Common attributes you'll need to add:

```hcl
resource "proxmox_virtual_environment_vm" "server1" {
  node_name = "node-02"
  vm_id     = 100
  name      = "my-server-1"

  # CPU — match what the plan showed
  cpu {
    cores   = 4
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  # Memory — match what the plan showed
  memory {
    dedicated = 4096
  }

  # Disk(s) — one block per disk interface on the VM
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 40
    file_format  = "raw"
  }

  # Network — match the bridge, VLAN, etc.
  network_device {
    bridge  = "vmbr0"
    vlan_id = 2
  }

  # QEMU guest agent
  agent {
    enabled = true
  }

  # Tags if any
  tags = ["k3s", "server"]
}
```

**Known gotchas with the bpg/proxmox provider:**

1. **Do NOT include a `clone` block.** If the VM was originally created by cloning a
   template, that information is not stored on the VM. Adding a `clone` block will cause
   Terraform to **destroy and recreate** the VM. If you already have one, either remove
   it or add `lifecycle { ignore_changes = [clone] }`.
   (See: https://github.com/bpg/terraform-provider-proxmox/issues/1131)

2. **Declare every disk interface** that exists on the VM, including CD-ROMs. If you
   declare fewer disks than actually exist, the provider's disk matching can get confused
   and propose deleting the wrong disk.
   (See: https://github.com/bpg/terraform-provider-proxmox/issues/2285)

3. **EFI disks** can trigger forced replacement on import because the provider can't
   fully read back EFI disk state. Use `lifecycle { ignore_changes = [efi_disk] }` if
   needed. (See: https://github.com/bpg/terraform-provider-proxmox/issues/1988)

4. **Timeout attributes** (like `agent.timeout`) may reset to defaults after import.
   This shows as drift but is non-destructive.

---

## Step 5: Repeat until plan shows no changes

**What you're doing:** Iterating on your HCL until Terraform considers your configuration
to be in sync with reality. This is the core learning loop — each `terraform plan` run
teaches you what attributes the provider cares about.

**How to do it:**

```bash
# Edit your resource blocks based on plan output...
terraform plan
# Still showing changes? Edit again...
terraform plan
# Repeat until you see:
#   Plan: 5 to import, 0 to add, 0 to change, 0 to destroy.
```

The target output is something like:

```
Plan: 5 to import, 0 to add, 0 to change, 0 to destroy.
```

- **5 to import** = your 5 VMs will be added to Terraform state (good)
- **0 to change** = your HCL matches reality exactly (good)
- **0 to destroy** = nothing will be deleted (critical — if you see destroys, STOP and investigate)

> **If you see "must be replaced" or "forces replacement":** This means Terraform wants to
> destroy and recreate a VM. This is usually caused by a `clone` block, an `efi_disk`
> mismatch, or a disk interface mismatch. Do NOT apply. Remove the offending attribute
> or add it to `lifecycle { ignore_changes = [...] }`.

**For attributes you can't perfectly match** (or that keep showing benign drift), use
`lifecycle` to suppress them:

```hcl
resource "proxmox_virtual_environment_vm" "server1" {
  # ... all your attributes ...

  lifecycle {
    ignore_changes = [
      clone,       # Never try to re-clone
      efi_disk,    # Can't be read back cleanly
    ]
  }
}
```

Use this sparingly — every ignored attribute is an attribute Terraform won't manage.

---

## Step 6: `terraform apply` to finalize the imports

**What you're doing:** Executing the import. Terraform reads each real VM from Proxmox
and writes its state into your Terraform state file (`.tfstate`). After this, Terraform
"owns" these VMs — future `plan` and `apply` runs will manage them.

**How to do it:**

```bash
terraform apply
```

Terraform will show the plan one more time and ask for confirmation. Review it carefully.
You should see:

```
Plan: 5 to import, 0 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes
```

Type `yes` to proceed. After completion you'll see:

```
Apply complete! Resources: 5 imported, 0 added, 0 changed, 0 destroyed.
```

**What just happened:**
- Terraform read the full state of each VM from the Proxmox API
- It wrote that state into your state file (local `terraform.tfstate` or remote backend)
- It did NOT modify the VMs themselves (assuming 0 changes in the plan)
- The VMs are now "managed resources" — any future drift between your HCL and the real
  VM will show up in `terraform plan`

**Verify it worked:**

```bash
# List all resources in state
terraform state list

# Inspect a specific imported VM
terraform state show 'proxmox_virtual_environment_vm.server1'

# Run plan again — should show no changes
terraform plan
```

---

## Step 7: Remove the `import` blocks

**What you're doing:** Cleaning up. The `import` blocks were a one-time instruction to
Terraform. Now that the resources are in state, the blocks serve no functional purpose.

**How to do it:**

Delete the `imports.tf` file (or remove the `import` blocks from wherever you placed them):

```bash
rm infrastructure/modules/pve/imports.tf
```

Then verify nothing changed:

```bash
terraform plan
# Should show: No changes. Your infrastructure matches the configuration.
```

**Why remove them?** Import blocks are idempotent — leaving them in won't break anything.
Terraform simply skips import blocks for resources that are already in state. However,
removing them keeps your configuration clean and avoids confusion for future readers.

> **Alternative: keep them as documentation.** Some teams prefer to leave import blocks
> in place as a record of which resources were imported rather than created by Terraform.
> This is a team preference — either approach is fine.

---

## Summary of the full workflow

```
1. Write skeleton resource blocks    -->  Tell Terraform what should exist
2. Add import blocks                 -->  Map each resource to a real VM
3. terraform plan                    -->  See what's different
4. Adjust HCL to match reality      -->  Fix the differences
5. Repeat 3-4 until 0 changes       -->  Iterate until clean
6. terraform apply                   -->  Execute the import
7. Remove import blocks              -->  Clean up
```

## Quick reference: import ID format

```
Provider: bpg/proxmox
Resource: proxmox_virtual_environment_vm
Import ID format: <node_name>/<vm_id>
Example: node-02/100
```
