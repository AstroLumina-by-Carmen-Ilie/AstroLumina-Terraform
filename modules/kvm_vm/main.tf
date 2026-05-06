# KVM VM Module - With Cloud-Init Autoinstall
# For dmacvicar/libvirt v0.9.x

terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
    }
  }
}

# ============================================================
# Cloud-Init ISO Volume (user-data + meta-data)
# ============================================================
resource "libvirt_volume" "cloudinit_iso" {
  name           = "${var.vm_name}-cloudinit.iso"
  pool          = var.disk_pool
  source        = var.cloudinit_iso_path
  format        = "raw"
}

# ============================================================
# OS Disk
# ============================================================
resource "libvirt_volume" "os_disk" {
  name           = var.vm_name
  pool          = var.disk_pool
  format        = "qcow2"
  base_volume_id = var.base_image_id
  size          = var.disk_gb * 1024 * 1024 * 1024
}

# ============================================================
# VM Domain
# ============================================================
resource "libvirt_domain" "this" {
  name       = var.vm_name
  memory    = var.memory_mb
  vcpu      = var.vcpu
  type      = "kvm"

  cloudinit = libvirt_volume.cloudinit_iso.id

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
  }

  boot_device = [
    { dev = "hd" }
  ]

  console {
    type        = "pty"
    target_port = 0
    target_type = "serial"
  }

  graphics {
    type    = "vnc"
    listen  = "0.0.0.0"
  }

  disk {
    volume_id = libvirt_volume.os_disk.id
    device    = "disk"
  }

  network_interface {
    network_id = var.network_id
    hostname = var.vm_name
  }
}

# ============================================================
# Firewall - allow SSH
# ============================================================
resource "libvirt_firewall" "ssh_allow" {
  name = "${var.vm_name}-allow-ssh"
  type = "accept"

  network_id = var.network_id
}