# KVM VM Module
# dmacvicar/libvirt v0.9.x

terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
    }
  }
}

# ============================================================
# Cloud-Init Disk (generates config ISO)
# ============================================================
resource "libvirt_cloudinit_disk" "this" {
  name = "${var.vm_name}-cloudinit"

  user_data = var.cloudinit_user_data != "" ? var.cloudinit_user_data : <<-EOF
#cloud-config
users:
  - name: ${var.ssh_username}
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin, sudo
    home: /home/${var.ssh_username}
    shell: /bin/bash
    ssh_authorized_keys:
      - ${var.ssh_pub_key}

ssh_pwauth: false

packages:
  - openssh-server
  - curl
  - wget
  - git
  - vim
  - net-tools
  - jq
  - ca-certificates

runcmd:
  - systemctl enable ssh
  - systemctl start ssh
EOF

  meta_data = yamlencode({
    instance-id    = var.vm_name
    local-hostname = var.vm_name
  })
}

# ============================================================
# Cloud-Init ISO Volume
# ============================================================
resource "libvirt_volume" "cloudinit_iso" {
  name = "${var.vm_name}-cloudinit.iso"
  pool = var.disk_pool

  create = {
    content = {
      url = libvirt_cloudinit_disk.this.path
    }
  }
}

# ============================================================
# OS Disk (copy from base image)
# ============================================================
resource "libvirt_volume" "os_disk" {
  name     = var.vm_name
  pool     = var.disk_pool
  capacity = var.disk_gb * 1024 * 1024 * 1024

  target = {
    format = {
      type = "qcow2"
    }
  }

  backing_store = var.base_image_path != "" ? {
    path = var.base_image_path
    format = {
      type = "qcow2"
    }
  } : null

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================
# VM Domain
# ============================================================
resource "libvirt_domain" "this" {
  name        = var.vm_name
  memory      = var.memory_mb
  memory_unit = "MiB"
  vcpu        = var.vcpu
  type        = "kvm"
  running     = var.running

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    boot_devices = [
      { dev = "hd" },
      { dev = "cdrom" }
    ]
  }

  devices = {
    disks = [
      {
        source = {
          volume = {
            pool   = var.disk_pool
            volume = libvirt_volume.os_disk.name
          }
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
        driver = {
          type = "qcow2"
        }
      },
      {
        device = "cdrom"
        source = {
          volume = {
            pool   = var.disk_pool
            volume = libvirt_volume.cloudinit_iso.name
          }
        }
        target = {
          dev = "sda"
          bus = "sata"
        }
      }
    ]

    interfaces = [
      {
        type  = "network"
        model = { type = "virtio" }
        source = {
          network = { network = var.network_name }
        }
      }
    ]

    graphics = [
      {
        vnc = {
          auto_port = true
          listen    = "0.0.0.0"
        }
      }
    ]

    consoles = [
      {
        type = "pty"
      }
    ]
  }
}

# ============================================================
# Data Source for IP Addresses (only when running)
# ============================================================
data "libvirt_domain_interface_addresses" "this" {
  count = var.running ? 1 : 0
  domain = libvirt_domain.this.id
  source = "lease"

  depends_on = [libvirt_domain.this]
}

# ============================================================
# Outputs
# ============================================================
output "vm_name" {
  description = "Numele VM-ului"
  value       = var.vm_name
}

output "ip_address" {
  description = "Adresa IP a VM-ului"
  value       = var.running ? try(data.libvirt_domain_interface_addresses.this[0].interfaces[0].addrs[0].addr, "N/A") : "VM oprit"
}

output "vcpu" {
  description = "Numărul de CPU-uri"
  value       = var.vcpu
}

output "memory_mb" {
  description = "Memoria în MB"
  value       = var.memory_mb
}

output "disk_gb" {
  description = "Dimensiunea discului în GB"
  value       = var.disk_gb
}