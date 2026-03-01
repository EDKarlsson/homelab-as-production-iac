resource "proxmox_virtual_environment_download_file" "ubuntu_2404_cloud_image" {
  content_type = "import"
  datastore_id = "Proxmox_NAS"
  node_name    = "node-02"
  url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name    = "noble-server-cloudimg-amd64.qcow2"
}


resource "proxmox_virtual_environment_vm" "ubuntu_2404_cloud_image" {
  name      = "ubuntu-2404-cloud-image"
  node_name = "node-02"
  # The ID of the VM. This must be unique across the cluster and is used to identify the VM in Proxmox.
  vm_id           = 9000
  template        = true
  started         = false
  stop_on_destroy = true
  agent {
    enabled = false
  }
  cpu {
    cores = 2
  }
  memory {
    dedicated = 2048
  }
  disk {
    datastore_id = "local-lvm"
    import_from  = proxmox_virtual_environment_download_file.ubuntu_2404_cloud_image.id
    interface    = "scsi0"
    ssd          = true
    iothread     = true
    discard      = "on"
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
