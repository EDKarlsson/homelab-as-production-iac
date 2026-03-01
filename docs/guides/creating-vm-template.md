# Guide: Creating a Ubuntu 24.04 VM Template via Terraform

This walkthrough covers how to create a reusable VM template from the Ubuntu 24.04 cloud
image using the `bpg/proxmox` provider. Once created, this template becomes the base image
that you clone to create your k3s nodes (covered in [Guide 3: Cloning k3s Node VMs](./cloning-k3s-vms.md)).

**What is a VM template?** A template is a read-only VM that acts as a "golden image." You
don't boot it — you clone it to create new VMs. Each clone gets an independent copy of the
disk and can be customized via cloud-init.
([Proxmox docs — VM Templates and Clones](https://pve.proxmox.com/wiki/VM_Templates_and_Clones))

**Why a cloud image instead of the server ISO?** Cloud images are pre-built, minimal OS
images designed for automated provisioning. They include `cloud-init` out of the box, which
lets Terraform inject SSH keys, hostnames, network config, and startup scripts without
manual installation. The server ISO (`ubuntu-24.04.1-live-server-amd64.iso` on your NAS)
requires an interactive installer.
([Ubuntu Cloud Images](https://cloud-images.ubuntu.com/noble/current/))

## Prerequisites

- Terraform >= 1.5 with `bpg/proxmox` provider v0.95.0 configured and `terraform init` completed
  (see [Terraform Provider Setup](./terraform-provider-setup.md))
- Proxmox API token with privileges: `Datastore.AllocateTemplate`, `Sys.Audit`, `Sys.Modify`,
  and `VM.Allocate` ([Provider docs — Authentication](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs#authentication))
- SSH agent access configured in your provider block (needed for file uploads and cross-node operations)

## Key documentation

| Topic | URL |
|---|---|
| `proxmox_virtual_environment_download_file` resource | https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_download_file |
| `proxmox_virtual_environment_vm` resource | https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm |
| `proxmox_virtual_environment_file` resource | https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_file |
| Proxmox — Cloud-Init Support | https://pve.proxmox.com/wiki/Cloud-Init_Support |
| Proxmox — VM Templates and Clones | https://pve.proxmox.com/wiki/VM_Templates_and_Clones |
| Ubuntu 24.04 Cloud Images | https://cloud-images.ubuntu.com/noble/current/ |

## Your storage layout

Before starting, here's what your Proxmox storage supports — this determines where each
resource gets created:

| Storage | Type | Supports `import` | Supports `snippets` | Supports `images` |
|---|---|---|---|---|
| `Proxmox_NAS` | NFS (shared) | **Yes** | **Yes** | **Yes** |
| `local` | Directory | No | No | No |
| `local-lvm` | LVM-thin | No | No | **Yes** |

This means:
- **Cloud image download** → must go to `Proxmox_NAS` (only storage with `import` content type)
- **Cloud-init snippets** → must go to `Proxmox_NAS` (only storage with `snippets` content type)
- **VM disks** → `local-lvm` (local SSD, better performance) or `Proxmox_NAS` (shared NFS)

> **Tip:** If you later want to download images to `local` instead, you can enable the
> `Import` content type in the Proxmox web UI: Datacenter → Storage → `local` → Edit →
> Content → add "Disk image import."
> ([Proxmox docs — Storage](https://pve.proxmox.com/wiki/Storage))

---

## Step 1: Download the Ubuntu 24.04 cloud image

**What you're doing:** Telling the bpg/proxmox provider to download the Ubuntu 24.04 cloud
image directly to your Proxmox storage. This uses the Proxmox download-url API — the file
goes straight to the Proxmox node, not through your local machine.

**Resource:** `proxmox_virtual_environment_download_file`
([Docs](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_download_file))

```hcl
resource "proxmox_virtual_environment_download_file" "ubuntu_2404_cloud_image" {
  content_type = "import"
  datastore_id = "Proxmox_NAS"
  node_name    = "node-02"
  url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name    = "noble-server-cloudimg-amd64.qcow2"
}
```

**Attribute explanations:**

- **`content_type = "import"`** — Tells Proxmox this is a disk image for importing into VMs,
  not an ISO. The file lands in the `import/` directory on the datastore. The target datastore
  must have the `Import` content type enabled (your `Proxmox_NAS` does).
  ([Docs — content_type](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_download_file#content_type))

- **`datastore_id = "Proxmox_NAS"`** — Your NFS share is the only storage with `import`
  enabled. Since it's shared storage, the downloaded file is accessible from all nodes.

- **`node_name = "node-02"`** — The Proxmox node that executes the download API call.
  Any node works since `Proxmox_NAS` is shared. Pick whichever node you want.

- **`url`** — The Ubuntu 24.04 (Noble Numbat) cloud image. This is a ~600MB qcow2 disk image
  despite the `.img` extension. It includes `cloud-init` pre-installed but does NOT include
  `qemu-guest-agent` (you'll install that via cloud-init on clones).
  ([Ubuntu Cloud Images — Noble](https://cloud-images.ubuntu.com/noble/current/))

- **`file_name = "noble-server-cloudimg-amd64.qcow2"`** — Renames the file from `.img` to
  `.qcow2` on download. This tells the Proxmox import system the actual disk format. The
  provider docs specifically recommend this rename.
  ([Docs — file_name](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_download_file#file_name))

**Optional: checksum verification.** You can add a SHA256 checksum to verify the download.
The checksum changes with each daily rebuild, so fetch it fresh:

```bash
curl -s https://cloud-images.ubuntu.com/noble/current/SHA256SUMS | grep "amd64.img"
```

Then add to your resource:

```hcl
  checksum           = "<sha256-hash-from-above>"
  checksum_algorithm = "sha256"
```

([Docs — checksum](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_download_file#checksum))

> **Note:** If you omit the checksum, the provider will still download the file but won't
> verify its integrity. For a homelab this is usually fine. For production, always verify.

---

## Step 2: Create the template VM

**What you're doing:** Creating a VM resource with `template = true`. This VM won't run —
it exists only as a base image for cloning. The disk is imported from the cloud image you
downloaded in Step 1. Hardware settings here are defaults — clones can override CPU, memory,
and disk size.

**Resource:** `proxmox_virtual_environment_vm` with `template = true`
([Docs](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm))

```hcl
resource "proxmox_virtual_environment_vm" "ubuntu_2404_template" {
  name        = "ubuntu-2404-cloud-template"
  description = "Ubuntu 24.04 LTS cloud image template. Managed by Terraform."
  tags        = ["terraform", "template", "ubuntu-2404"]
  node_name   = "node-02"
  vm_id       = 9000

  template        = true
  started         = false
  stop_on_destroy = true

  cpu {
    cores   = 2
    sockets = 1
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = 2048
  }

  agent {
    enabled = false
  }

  disk {
    datastore_id = "local-lvm"
    import_from  = proxmox_virtual_environment_download_file.ubuntu_2404_cloud_image.id
    interface    = "scsi0"
    discard      = "on"
    ssd          = true
    iothread     = true
  }

  scsi_hardware = "virtio-scsi-single"

  network_device {
    bridge = "vmbr0"
  }

  vga {
    type = "serial0"
  }

  serial_device {}

  operating_system {
    type = "l26"
  }
}
```

**Attribute explanations:**

**Template & lifecycle:**

- **`template = true`** — Converts this VM into a Proxmox template after creation. Templates
  are read-only and cannot be started — they can only be cloned.
  ([Docs — template](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#template))

- **`started = false`** — Templates must not be started. If you set `started = true` with
  `template = true`, Terraform will try to start a template and fail.

- **`stop_on_destroy = true`** — Ensures the VM can be cleanly removed during `terraform
  destroy`. Without this, destruction may hang if the guest agent isn't running.
  ([Docs — stop_on_destroy](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#stop_on_destroy))

- **`vm_id = 9000`** — Convention in your existing k3s module (`var.k3s_template_vm_id`
  defaults to 9000). Proxmox VM IDs are cluster-wide, so pick a number that won't collide
  with existing VMs/CTs (your only existing one is LXC 100).

**CPU & memory:**

- **`cores = 2`, `dedicated = 2048`** — Minimal defaults for the template. Clones will
  override these with their own specs (4 CPU, 8GB+ for k3s). Template hardware config is
  just a starting point.
  ([Docs — cpu](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#cpu),
  [Docs — memory](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#memory))

- **`type = "x86-64-v2-AES"`** — CPU type that works across all your nodes (mixed hardware).
  This is the pattern used in your existing k3s module. It exposes a generic x86-64-v2
  feature set with AES-NI, ensuring live migration compatibility across nodes.

**Guest agent:**

- **`agent { enabled = false }`** — The Ubuntu cloud image does NOT include `qemu-guest-agent`.
  If you set `enabled = true` without the agent installed, every Terraform operation will
  hang for up to 15 minutes waiting for the agent to respond. Install the agent via cloud-init
  on clones, then enable it there.
  ([Docs — agent](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#agent))

> **Warning from provider docs:** *"Do not run VM with agent.enabled = true, unless the VM
> is configured to automatically start qemu-guest-agent."* This is a common mistake that
> causes Terraform to appear frozen.

**Disk:**

- **`import_from`** — References the downloaded cloud image. The provider imports this qcow2
  image into `local-lvm` as the VM's boot disk. You use `import_from` (not `file_id`) because
  the image was downloaded with `content_type = "import"`.
  ([Docs — disk.import_from](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_download_file#usage-with-proxmox_virtual_environment_vm-disk-import))

- **`datastore_id = "local-lvm"`** — The actual VM disk lives on the node's local LVM thin
  pool, not on NFS. This gives better I/O performance for the template's base disk. When
  you clone to other nodes, Proxmox copies the disk to that node's `local-lvm`.

- **`interface = "scsi0"`** — SCSI interface. Combined with `scsi_hardware = "virtio-scsi-single"`,
  this gives the best performance for cloud workloads.

- **`discard = "on"`, `ssd = true`, `iothread = true`** — Enable TRIM/discard passthrough
  (important for thin-provisioned LVM), SSD emulation, and dedicated I/O threads per disk.
  These attributes must be re-specified on clones — see [Guide 3](./cloning-k3s-vms.md#step-4-define-the-clone-vms).
  ([Docs — disk](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#disk))

**SCSI controller:**

- **`scsi_hardware = "virtio-scsi-single"`** — The VirtIO SCSI single controller gives each
  disk its own I/O thread (when `iothread = true`). This is the recommended controller for
  modern Linux guests.
  ([Docs — scsi_hardware](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#scsi_hardware))

**Network:**

- **`bridge = "vmbr0"`** — Your standard Proxmox network bridge. No VLAN is set on the
  template — clones will add VLAN tagging as needed. Your existing k3s module uses VLAN 2.
  ([Docs — network_device](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#network_device))

**Console:**

- **`vga { type = "serial0" }` + `serial_device {}`** — Redirects the display to a serial
  console. Cloud images don't have a graphical desktop, so a serial console is sufficient
  and uses fewer resources. This also enables `qm terminal <vmid>` access from the Proxmox
  host.
  ([Docs — vga](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#vga),
  [Docs — serial_device](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#serial_device))

**Operating system:**

- **`type = "l26"`** — Tells Proxmox this is a Linux 2.6+ / 6.x kernel guest. This enables
  Linux-specific optimizations in QEMU/KVM.
  ([Docs — operating_system](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#operating_system))

**What's NOT included (intentionally):**

- **No `initialization` block** — Cloud-init configuration is set per-clone, not on the
  template. Each k3s node needs its own hostname, IP address, and cloud-init scripts.
  See [Guide 3](./cloning-k3s-vms.md) for cloud-init setup.
- **No `clone` block** — This VM is created from a cloud image import, not cloned from
  another template.
- **No `efi_disk`** — The Ubuntu cloud image supports both BIOS and UEFI boot. Omitting
  EFI disk uses legacy BIOS boot, which avoids known provider issues where EFI disk
  parameters can't be fully read back from Proxmox, causing forced recreation on subsequent
  applies.
  ([GitHub issue #1515](https://github.com/bpg/terraform-provider-proxmox/issues/1515))

---

## Step 3: Plan and apply

**What you're doing:** Running `terraform plan` to preview what Terraform will create, then
`terraform apply` to execute. This creates two things in Proxmox: the downloaded cloud image
file and the template VM.

```bash
cd infrastructure
terraform plan
```

**What you should see in the plan:**

```
Plan: 2 to add, 0 to change, 0 to destroy.

  # proxmox_virtual_environment_download_file.ubuntu_2404_cloud_image will be created
  # proxmox_virtual_environment_vm.ubuntu_2404_template will be created
```

Review the plan carefully. You should see:
- The download_file resource creating on `Proxmox_NAS`
- The VM resource creating on `node-02` with `template = true`
- The disk importing from the downloaded file into `local-lvm`

If the plan looks correct:

```bash
terraform apply
```

The download step may take a few minutes (the cloud image is ~600MB, downloading directly
to your NAS). The VM creation and template conversion should be fast.

**Verify in Proxmox UI:**
1. Open the Proxmox web UI
2. Look for VM 9000 (`ubuntu-2404-cloud-template`) on `node-02`
3. It should show as a template (template icon, not a regular VM)
4. Check Hardware tab: should show the SCSI disk, network device, and no cloud-init drive

**Verify via Terraform:**

```bash
terraform state list
# Should show:
#   proxmox_virtual_environment_download_file.ubuntu_2404_cloud_image
#   proxmox_virtual_environment_vm.ubuntu_2404_template

terraform state show 'proxmox_virtual_environment_vm.ubuntu_2404_template'
```

---

## Gotchas and tips

1. **`import` content type must be enabled on your datastore.** Your `Proxmox_NAS` already
   has it. If you switch to `local`, you'll need to enable it in the Proxmox UI first.
   The provider will return a cryptic error if the content type is missing.
   ([Docs — download_file](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_download_file))

2. **The cloud image URL points to `current/` — it changes with each daily rebuild.** If you
   apply again later, the provider may re-download if the file size changed. Pin to a dated
   release (e.g., `https://cloud-images.ubuntu.com/noble/20250213/`) if you want a stable
   image. Adding a checksum prevents unexpected re-downloads.
   ([Ubuntu release list](https://cloud-images.ubuntu.com/noble/))

3. **Don't set `agent { enabled = true }` on the template.** The cloud image has no guest
   agent installed. Enabling it causes Terraform to hang waiting for agent communication.
   Enable it on clones after cloud-init installs `qemu-guest-agent`.

4. **Template hardware is just defaults.** CPU cores, memory, and disk size set on the
   template are starting values. Clones override them. Keep the template minimal (2 CPU,
   2GB RAM) — you'll set the real specs (4 CPU, 8GB RAM, 100GB disk) on each clone.

5. **Cross-node cloning with `local-lvm`.** Your template's disk lives on `node-02`'s
   `local-lvm`. When you clone to other nodes (e.g., `node-01`), the provider first
   clones the VM locally on the source node via the Proxmox API, then migrates it to the
   target node (also via the API). The disk is copied to the target node's `local-lvm`
   during migration. This is handled entirely through the Proxmox REST API — no SSH is
   required for this operation (SSH is needed for other provider features like snippet uploads).
   ([Docs — clone](https://registry.terraform.io/providers/bpg/proxmox/0.95.0/docs/resources/virtual_environment_vm#clone))

> **Uncertainty:** I have not personally verified cross-node cloning behavior with `local-lvm`
> in provider v0.95.0. If you hit issues, an alternative is to store the template disk on
> `Proxmox_NAS` (shared storage) so all nodes can access it directly. Trade-off: NFS is
> slower than local SSD for disk I/O during clone.

---

---

## Future: 1Password integration

The Proxmox API credentials used by Terraform to create this template are currently passed via
`TF_VAR_*` environment variables. With the 1Password provider (already configured in `main.tf`),
you can read them directly from 1Password at plan/apply time, eliminating the need for credential
environment variables beyond the Connect token itself.

See [Guide 6: 1Password Secrets Management — Terraform Integration](./1password-secrets-management.md#part-3-terraform-integration)
for the full pattern.

---

## What's next

Continue to [Guide 3: Cloning k3s Node VMs from Template](./cloning-k3s-vms.md).
