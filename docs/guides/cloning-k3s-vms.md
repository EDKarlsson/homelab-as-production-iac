# Guide: Cloning k3s Node VMs from Template

This walkthrough covers how to clone the Ubuntu 24.04 template (from
[Guide 2: Creating a VM Template](./creating-vm-template.md)) into VMs for your k3s cluster.
Each clone gets customized via cloud-init with its own hostname, static IP, SSH access, and
base packages. After Terraform creates these VMs, Ansible takes over for k3s provisioning.

## Prerequisites

- Completed [Guide 2](./creating-vm-template.md) (template VM `ubuntu-2404-cloud-template` exists at VM ID 9000)
- SSH public key available as a Terraform variable or file
- Decided on IP address allocation for your k3s nodes

## Key documentation

| Topic | URL |
|---|---|
| `proxmox_virtual_environment_vm` — clone block | https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#clone |
| `proxmox_virtual_environment_vm` — initialization block | https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#initialization |
| `proxmox_virtual_environment_vm` — disk block | https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#disk |
| `proxmox_virtual_environment_file` resource | https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_file |
| Terraform `for_each` meta-argument | https://developer.hashicorp.com/terraform/language/meta-arguments/for_each |
| Terraform `templatefile` function | https://developer.hashicorp.com/terraform/language/functions/templatefile |
| Terraform `index` function | https://developer.hashicorp.com/terraform/language/functions/index |
| cloud-init modules reference | https://cloudinit.readthedocs.io/en/latest/reference/modules.html |
| Proxmox — Cloud-Init Support | https://pve.proxmox.com/wiki/Cloud-Init_Support |

---

## Step 1: Plan your VM layout

**What you're doing:** Defining the parameters for your k3s VMs in a `locals` block —
node placement, IP addresses, VM IDs, and network config. This keeps all your allocation
decisions in one place and feeds into `for_each` loops.

```hcl
locals {
  # Which Proxmox nodes get a k3s VM
  proxmox_nodes = [
    "node-01",
    "node-02",
    "node-03",
    "node-04",
    "node-05"
  ]

  # Template location
  template_vm_id    = 9000              # From Guide 2
  template_node     = "node-02"  # Node where the template lives

  # Network (VLAN 2 - Homelab)
  k3s_network = {
    vlan_id = 2
    subnet  = "10.0.0.0/24"
    gateway = "10.0.0.1"
  }

  # Static IP assignments — one per node
  # Produces: { "node-01" = "10.0.0.50", "node-02" = "10.0.0.51", ... }
  k3s_node_ips = {
    for i, node in local.proxmox_nodes : node => "10.0.0.${50 + i}"
  }
}
```

**IP allocation strategy:** The `for` expression uses each node's list index to compute an
IP in the `.50-.54` range. Adjust the base (`50`) and range to fit your network plan.
([Terraform — `for` expressions](https://developer.hashicorp.com/terraform/language/expressions/for))

**VM ID strategy:** In Step 4, each clone gets `vm_id = 500 + index(...)`, producing IDs
500-504. This follows the convention from your existing k3s module. Proxmox VM IDs are
cluster-wide and must be unique — check for collisions with existing VMs/CTs (your current
environment only has LXC 100).
([Terraform — `index` function](https://developer.hashicorp.com/terraform/language/functions/index))

> **Note:** This guide creates 5 VMs (one per node). If you want separate server and agent
> VMs (10 total, like your existing `modules/k3s/k3s-cluster.tf` reference), create two
> `proxmox_virtual_environment_vm` resources with different name prefixes, VM ID ranges
> (e.g., 500s for servers, 510s for agents), and IP ranges (e.g., .50s and .60s). The
> pattern is the same — duplicate the resource block with different locals.

---

## Step 2: Write the cloud-init template file

**What you're doing:** Creating a cloud-init `#cloud-config` YAML template that configures
each VM on first boot. This handles everything the base cloud image doesn't include:
user account, SSH access, `qemu-guest-agent`, NFS mount, and basic packages.

Create a template file (e.g., `k3s-node.yml.tpl`) with the following content:

```yaml
#cloud-config
hostname: ${hostname}
fqdn: ${hostname}.homelab.local
manage_etc_hosts: true

users:
  - name: ${username}
    groups: [adm, sudo]
    lock_passwd: true
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ${ssh_public_key}

package_update: true
package_upgrade: true

packages:
  - qemu-guest-agent
  - nfs-common
  - curl
  - jq
  - htop
  - net-tools

runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - mkdir -p /mnt/nfs/proxmox

mounts:
  - [ "10.0.0.161:/volume1/proxmox", "/mnt/nfs/proxmox", "nfs", "defaults,_netdev,noatime", "0", "0" ]
```

**Section-by-section explanation:**

- **`hostname` / `fqdn` / `manage_etc_hosts`** — Sets the VM's hostname and updates
  `/etc/hosts` to match. The `${hostname}` variable is rendered per-VM by `templatefile()`.
  ([cloud-init — set_hostname module](https://cloudinit.readthedocs.io/en/latest/reference/modules.html#set-hostname))

- **`users`** — Creates your admin user with passwordless sudo and SSH key authentication.
  `lock_passwd: true` disables password login (SSH key only). This replaces the
  `user_account` block in the `initialization` block — more on why in Step 4.
  ([cloud-init — users and groups module](https://cloudinit.readthedocs.io/en/latest/reference/modules.html#users-and-groups))

- **`packages`** — Installs packages on first boot. `qemu-guest-agent` is critical — without
  it, Terraform can't query the VM's IP address or manage its power state. `nfs-common` is
  required for NFS mounts. The rest are utilities you'll want for debugging.
  ([cloud-init — package update upgrade install module](https://cloudinit.readthedocs.io/en/latest/reference/modules.html#package-update-upgrade-install))

- **`runcmd`** — Runs commands after package installation. Enables and starts the guest
  agent immediately so Terraform doesn't have to wait for a reboot. Creates the NFS mount
  point directory.
  ([cloud-init — runcmd module](https://cloudinit.readthedocs.io/en/latest/reference/modules.html#runcmd))

- **`mounts`** — Adds an entry to `/etc/fstab` and mounts the NFS share. The format matches
  fstab columns: `[device, mountpoint, type, options, dump, fsck]`. The `_netdev` option
  tells systemd to wait for the network before mounting. `noatime` reduces unnecessary
  write operations.
  ([cloud-init — mounts module](https://cloudinit.readthedocs.io/en/latest/reference/modules.html#mounts))

  The NFS server `10.0.0.161:/volume1/proxmox` is your `Proxmox_NAS` storage backend.
  Adjust the mount point (`/mnt/nfs/proxmox`) and NFS path if needed.

**Template variables** that `templatefile()` will inject:

| Variable | Source | Example value |
|---|---|---|
| `hostname` | Computed from VM name | `k3s-node-node-01` |
| `username` | Your admin username variable | `dank` |
| `ssh_public_key` | Your SSH public key variable | `ssh-ed25519 AAAA...` |

**Where to put this file:** Follow the existing codebase pattern — template files live in
`modules/cloud-configs/`. So: `infrastructure/modules/cloud-configs/k3s-node.yml.tpl`.
Or place it alongside your module. The path is passed to `templatefile()` in Step 3, so
it just needs to be reachable via `${path.module}/...`.

> **Ansible readiness:** Ubuntu 24.04 cloud images include Python 3 by default, which is
> all Ansible needs to connect. After cloud-init runs, your VM has SSH access + Python —
> ready for Ansible playbooks. Any k3s-specific setup (kernel modules, sysctl tuning, swap
> disabling) can be handled by your Ansible k3s role rather than cloud-init.

---

## Step 3: Upload cloud-init snippets to Proxmox

**What you're doing:** Using `proxmox_virtual_environment_file` to render your template
file (with per-VM variables) and upload the result to Proxmox's snippet storage. Each VM
gets its own cloud-config file with its unique hostname.

**Resource:** `proxmox_virtual_environment_file`
([Docs](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_file))

```hcl
resource "proxmox_virtual_environment_file" "k3s_cloud_config" {
  for_each = toset(local.proxmox_nodes)

  content_type = "snippets"
  datastore_id = "Proxmox_NAS"
  node_name    = each.key

  source_raw {
    data = templatefile("${path.module}/../cloud-configs/k3s-node.yml.tpl", {
      hostname       = "k3s-node-${each.key}"
      username       = var.vm_username
      ssh_public_key = trimspace(var.ssh_public_key)
    })

    file_name = "k3s-node-${each.key}.yml"
  }
}
```

**Attribute explanations:**

- **`content_type = "snippets"`** — Cloud-init user-data files are stored as Proxmox
  "snippets." Your `Proxmox_NAS` is the only datastore with the `snippets` content type
  enabled (see [storage table in Guide 2](./creating-vm-template.md#your-storage-layout)).
  ([Docs — content_type](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_file#content_type))

- **`for_each = toset(local.proxmox_nodes)`** — Creates one snippet resource per node. Since
  `Proxmox_NAS` is shared NFS, uploading to multiple nodes writes the same file path. This
  is redundant but keeps the provider's state tracking clean — each resource is tied to a
  specific node.

- **`node_name = each.key`** — The provider uses SSH to upload snippet files to the target
  node. This requires the `ssh` block in your provider configuration.
  ([Docs — node_name](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_file#node_name))

- **`source_raw { data = templatefile(...) }`** — Renders the `.yml.tpl` template with
  per-VM variables and passes the result as inline content. `templatefile()` replaces
  `${hostname}`, `${username}`, and `${ssh_public_key}` with actual values.
  ([Terraform — templatefile](https://developer.hashicorp.com/terraform/language/functions/templatefile))

- **`trimspace(var.ssh_public_key)`** — Removes trailing newlines from the SSH key. A
  trailing newline in the key string breaks cloud-init's YAML parsing. This is a common
  gotcha from the existing codebase.

- **`file_name`** — The name of the snippet file in the datastore. Each VM gets a unique
  name (e.g., `k3s-node-node-01.yml`). This file is referenced by its full Proxmox
  volume ID: `Proxmox_NAS:snippets/k3s-node-node-01.yml`.

> **Note about snippet storage:** If `snippets` is not enabled on `Proxmox_NAS`, you'll get
> an error like `"the requested resource does not exist."` Enable it in the Proxmox UI:
> Datacenter → Storage → Proxmox_NAS → Edit → Content → check "Snippets."
> Your `Proxmox_NAS` already has it enabled.

---

## Step 4: Define the clone VMs

**What you're doing:** Creating a `proxmox_virtual_environment_vm` resource that clones
the template from [Guide 2](./creating-vm-template.md) once per Proxmox node, customizes
each clone with the target specs (4 CPU, 8GB RAM, 100GB disk), and applies cloud-init for
first-boot configuration.

```hcl
resource "proxmox_virtual_environment_vm" "k3s_nodes" {
  for_each = toset(local.proxmox_nodes)

  name        = "k3s-node-${each.key}"
  description = "K3s cluster node on ${each.key}. Managed by Terraform."
  tags        = ["k3s", "terraform", "homelab"]
  node_name   = each.key
  vm_id       = 500 + index(local.proxmox_nodes, each.key)

  clone {
    vm_id        = local.template_vm_id
    node_name    = local.template_node
    datastore_id = "local-lvm"
    full         = true
  }

  started         = true
  stop_on_destroy = true

  agent {
    enabled = true
    timeout = "15m"
  }

  cpu {
    cores   = 4
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 100
    file_format  = "raw"
    discard      = "on"
    ssd          = true
    iothread     = true
  }

  network_device {
    bridge  = "vmbr0"
    vlan_id = local.k3s_network.vlan_id
  }

  initialization {
    datastore_id = "local-lvm"

    dns {
      domain  = "homelab.local"
      servers = ["10.0.0.1"]
    }

    ip_config {
      ipv4 {
        address = "${lookup(local.k3s_node_ips, each.key)}/24"
        gateway = local.k3s_network.gateway
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.k3s_cloud_config[each.key].id
  }
}
```

**Attribute explanations — clone block:**

- **`clone.vm_id`** — The VM ID of the source template (9000 from [Guide 2](./creating-vm-template.md)).
  The provider reads this template's disk and configuration as the base for the clone.
  ([Docs — clone.vm_id](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#clone))

- **`clone.node_name`** — The **source** node where the template lives. This is NOT the
  target node (that's the top-level `node_name`). For cross-node cloning, you must set this
  explicitly. If the template is on `node-02` and you're cloning to `node-01`,
  the provider first clones locally on the source node, then migrates via the Proxmox API
  to the target.
  ([Docs — clone.node_name](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#clone))

- **`clone.datastore_id = "local-lvm"`** — Where to place the cloned disk during the
  clone+migrate operation. The docs recommend setting this explicitly for cross-node clones:
  *"It is recommended to set the `datastore_id` argument in the `clone` block to force the
  migration step to migrate all disks to a specific datastore on the target node."*
  ([Docs — clone.datastore_id](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#clone))

- **`clone.full = true`** — Creates an independent full copy of the template's disk. A linked
  clone (`full = false`) shares the base image with the template, saving disk space but
  creating a dependency. Full clones are recommended for production — each VM is self-contained.
  ([Proxmox — VM Templates and Clones](https://pve.proxmox.com/wiki/VM_Templates_and_Clones))

**Attribute explanations — agent:**

- **`agent { enabled = true, timeout = "15m" }`** — Enables the QEMU guest agent. Unlike the
  template (where we set `enabled = false` — see [Guide 2](./creating-vm-template.md#step-2-create-the-template-vm)),
  the clones have `qemu-guest-agent` installed by cloud-init. The agent lets Terraform query
  the VM's IP address and request graceful shutdown. The `timeout` gives cloud-init up to 15
  minutes to install and start the agent on first boot.
  ([Docs — agent](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#agent))

> **Warning:** If cloud-init fails to install or start `qemu-guest-agent`, Terraform will
> hang for the full timeout duration (15 minutes) on every operation. If this happens, check
> the cloud-init log inside the VM: `cat /var/log/cloud-init-output.log`.

**Attribute explanations — disk:**

- **`size = 100`** — Resizes the cloned disk from the template's ~2.5GB (cloud image size)
  to 100GB. The provider issues a Proxmox `resize` API call after cloning. The guest OS
  handles the rest automatically: Ubuntu cloud images include cloud-init's `growpart` and
  `resizefs` modules, which expand the partition and filesystem to fill the new disk on
  first boot.
  ([cloud-init — growpart module](https://cloudinit.readthedocs.io/en/latest/reference/modules.html#growpart),
  [cloud-init — resizefs module](https://cloudinit.readthedocs.io/en/latest/reference/modules.html#resizefs))

- **`datastore_id = "local-lvm"`** — Always set this explicitly on clone disks. There is a
  known open issue ([#2225](https://github.com/bpg/terraform-provider-proxmox/issues/2225))
  where omitting `datastore_id` causes the provider to compare against the schema default
  and trigger a spurious `move_disk` operation that fails.

- **`file_format = "raw"`** — LVM thin provisioning (`local-lvm`) only supports `raw` format.
  This must match the storage backend. Setting it explicitly avoids provider inference issues.

- **All non-default attributes must be re-specified.** When you modify any attribute on a
  cloned disk (like `size`), the provider applies schema defaults to any unspecified
  attributes. From the docs: *"If you modify any attributes of an existing disk in the
  clone, you also need to explicitly provide values for any other attributes that differ
  from the schema defaults."* If you omit `discard`, it reverts to `"ignore"`. If you omit
  `iothread`, it reverts to `false`. The attributes above (`discard`, `ssd`, `iothread`)
  match the template from [Guide 2](./creating-vm-template.md) — keep them in sync.
  ([Docs — disk](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#disk))

- **No `import_from` or `file_id`** — These are for creating VMs from disk images
  ([Guide 2](./creating-vm-template.md)). On clones, the disk comes from the template.
  Do not include them.

**Attribute explanations — initialization (cloud-init):**

- **`initialization.datastore_id = "local-lvm"`** — Where to store the cloud-init drive
  (a small ISO image that Proxmox attaches to the VM). Setting this explicitly avoids a
  known issue ([#1462](https://github.com/bpg/terraform-provider-proxmox/issues/1462))
  where cloning to non-default datastores produces cryptic errors.

- **`dns`** — DNS servers and search domain injected via Proxmox's cloud-init network
  configuration. Adjust `servers` to match your network's DNS. The existing k3s module
  uses `["10.0.0.10", "10.0.0.11"]` — update to your actual DNS server IPs.
  ([Docs — initialization.dns](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#initialization))

- **`ip_config`** — Assigns a static IPv4 address to each VM. `lookup()` fetches the IP
  from the `k3s_node_ips` map based on the current node. CIDR suffix `/24` must be included.
  `gateway` is your VLAN 2 gateway.
  ([Docs — initialization.ip_config](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#initialization))

- **`user_data_file_id`** — Points to the rendered cloud-init snippet from Step 3. This is
  the cloud-config file that handles user creation, package installation, and NFS mount.
  The `[each.key]` index matches the corresponding snippet for this node.

**Why `user_data_file_id` instead of `user_account`:**

In provider v0.95.0, `user_data_file_id` and `user_account` are **mutually exclusive** —
the provider enforces a conflict between them. From the docs:

> *`user_data_file_id` — (Optional) The identifier for a file containing custom user data
> (conflicts with `user_account`).*
>
> ([Docs — initialization](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#initialization))

Since you need custom cloud-init for packages, NFS mounts, and `runcmd` (which `user_account`
can't provide), you must use `user_data_file_id`. User creation and SSH keys are handled
in the cloud-config template (Step 2) instead.

> **Note about the existing `modules/k3s/k3s-cluster.tf` reference:** That file uses both
> `user_account` and `user_data_file_id` together. This was likely written for an older
> provider version. In v0.95.0, this will produce a validation error. Use `user_data_file_id`
> alone and handle user setup in your cloud-config template.

Similarly, `ip_config` and `network_data_file_id` conflict — you can use one or the other.
We use `ip_config` because it's simpler for static IP assignment (no extra template file
needed for network config).

---

## Step 5: Plan and apply

```bash
cd infrastructure
terraform plan
```

**What you should see in the plan:**

```
Plan: 10 to add, 0 to change, 0 to destroy.

  # proxmox_virtual_environment_file.k3s_cloud_config["node-01"] will be created
  # proxmox_virtual_environment_file.k3s_cloud_config["node-02"] will be created
  # ... (5 snippet files total)
  # proxmox_virtual_environment_vm.k3s_nodes["node-01"] will be created
  # proxmox_virtual_environment_vm.k3s_nodes["node-02"] will be created
  # ... (5 VMs total)
```

10 resources: 5 cloud-init snippet files + 5 VMs.

Review the plan and confirm:
- Each VM targets the correct node (`node_name = each.key`)
- The clone references the template (VM ID 9000 on `node-02`)
- Disk size is 100GB
- IP addresses are correct (.50 through .54)
- Cloud-init snippets are on `Proxmox_NAS`

```bash
terraform apply
```

**Timing expectations:** Cross-node cloning is slower than same-node cloning. Each VM
requires: clone template → migrate to target node → resize disk → boot → wait for
cloud-init + guest agent. Expect 5-10 minutes per VM. Since Terraform creates independent
resources in parallel (up to the parallelism limit), all 5 VMs may be provisioning
simultaneously.

**Verify the VMs:**

```bash
# Check Terraform state
terraform state list | grep k3s_nodes
terraform output  # If you've defined outputs

# SSH into a VM (use the IP from your locals)
ssh <username>@10.0.0.50

# Inside the VM, verify cloud-init completed
cloud-init status
cat /var/log/cloud-init-output.log

# Verify qemu-guest-agent is running
systemctl status qemu-guest-agent

# Verify NFS mount
df -h | grep nfs
ls /mnt/nfs/proxmox
```

---

## Gotchas

1. **`user_account` and `user_data_file_id` conflict in v0.95.0.** You cannot use both in
   the same `initialization` block. The provider will reject the configuration at plan time.
   Put all user setup (account creation, SSH keys) in your cloud-config template file and
   reference it via `user_data_file_id`.
   ([Docs — initialization](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#initialization))

2. **Re-specify all non-default disk attributes on clones.** When you set any attribute on a
   cloned disk (like `size`), the provider applies schema defaults to anything you don't
   specify. If your template has `discard = "on"` but the clone's disk block doesn't include
   it, the provider will try to change it to `"ignore"` (the default). Copy all non-default
   disk attributes from the template to the clone.
   ([Docs — disk](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#disk))

3. **Always set `disk.datastore_id` explicitly on clones.** Omitting it can trigger issue
   [#2225](https://github.com/bpg/terraform-provider-proxmox/issues/2225), where the
   provider compares against the schema default and attempts a spurious disk move that fails.

4. **Set `clone.datastore_id` for cross-node clones.** The provider docs recommend this to
   ensure disks are migrated to the correct storage on the target node. Without it, the
   provider may leave disks on the source node's storage after migration.
   ([Docs — clone.datastore_id](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#clone))

5. **Disk resize happens at the block device level only.** Terraform/Proxmox grows the QEMU
   virtual disk to 100GB. The guest OS must expand the partition and filesystem to use the
   new space. Ubuntu cloud images handle this automatically via cloud-init's `growpart` and
   `resizefs` modules on first boot. If you use a non-cloud image, you'd need to resize
   manually.
   ([cloud-init — growpart](https://cloudinit.readthedocs.io/en/latest/reference/modules.html#growpart))

6. **Cloud-init runs only on first boot (by default).** If you change the cloud-init template
   and run `terraform apply`, the snippet file in Proxmox updates, but the VM does not re-run
   cloud-init. To re-apply cloud-init changes, you must either: recreate the VM (`terraform
   taint`), or manually run `cloud-init clean && cloud-init init` inside the VM.
   ([cloud-init — boot stages](https://cloudinit.readthedocs.io/en/latest/explanation/boot.html))

7. **Terraform may appear frozen during first apply.** After cloning, Terraform waits for the
   guest agent to report in (up to the `timeout` value — 15 minutes). During this time,
   cloud-init is installing packages and starting the agent. This is normal. If it times out,
   SSH into the VM and check `cloud-init status` and `systemctl status qemu-guest-agent`.

8. **`dns.server` (singular) is deprecated.** Use `dns.servers` (a list) instead. The
   provider still accepts the deprecated field but may remove it in a future version.
   ([Docs — initialization.dns](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#initialization))

> **Uncertainty — disk resize on clones:** Disk resizing after clone has been a historically
> buggy area in the bpg/proxmox provider. v0.95.0 includes a fix
> ([PR #2563](https://github.com/bpg/terraform-provider-proxmox/pull/2563)) for a reversion
> bug where pending changes could undo the resize. If you encounter issues, workarounds
> include: (a) applying in two stages — first create the clone with the template's original
> disk size, then change `size` and re-apply; or (b) resizing the disk manually via the
> Proxmox UI after clone and importing the new size into state.

---

## What's next

With the VMs running, you're ready for Ansible. Your VMs have:
- SSH access via your public key
- `qemu-guest-agent` running (Terraform can manage them)
- NFS share mounted at `/mnt/nfs/proxmox`
- Static IPs on VLAN 2
- 4 CPUs, 8GB RAM, 100GB disk
- Ubuntu 24.04 with Python 3 (Ansible-ready)

Next steps for Ansible k3s provisioning:
1. Build an Ansible inventory from the Terraform outputs (IPs, hostnames, node roles)
2. Decide which nodes are k3s servers vs agents
3. Run your k3s Ansible role/playbook

---

## Future: 1Password integration

### Reading SSH keys from 1Password

Instead of passing `var.ssh_public_key` as a Terraform variable, you can read it directly from
1Password using a data source. Your Homelab vault already has the SSH credentials stored under
item `OP_PROXMOX_SSH`:

```hcl
data "onepassword_item" "proxmox_ssh" {
  vault = data.onepassword_vault.homelab.uuid
  title = "Proxmox SSH"
}

# Reference in cloud-init template
resource "proxmox_virtual_environment_file" "k3s_cloud_config" {
  # ...
  source_raw {
    data = templatefile("${path.module}/../cloud-configs/k3s-node.yml.tpl", {
      hostname       = "k3s-node-${each.key}"
      username       = var.vm_username
      ssh_public_key = data.onepassword_item.proxmox_ssh.public_key  # From 1Password
    })
  }
}
```

> **Uncertainty:** The exact field name for the SSH public key depends on how the item is
> structured in 1Password. Check `op item get ${OP_PROXMOX_SSH} --vault ${OP_VAULT_HOMELAB}`
> to see available fields.

### Storing the K3s cluster token

If you generate a K3s token via Terraform (`random_password`), you can store it in 1Password
for use by Ansible later:

```hcl
resource "onepassword_item" "k3s_token" {
  vault    = data.onepassword_vault.homelab.uuid
  category = "password"
  title    = "K3s Cluster Token"
  password = random_password.k3s_token.result
  tags     = ["k3s", "terraform-managed"]
}
```

See [Guide 6: 1Password Secrets Management](./1password-secrets-management.md) for the full
pattern including how Ansible reads this token back via the Connect lookup plugin.
