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
# Cloud-Init Disk (generates ISO)
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
    lock_passwd: false
    plain_text_passwd: ${var.ssh_password}
    ssh_authorized_keys:
      - ${var.ssh_pub_key}

chpasswd:
  expire: false

ssh_pwauth: true

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
# Cloud-Init ISO Volume (from generated disk)
# ============================================================
resource "libvirt_volume" "cloudinit_iso" {
  name   = "${var.vm_name}-cloudinit.iso"
  pool   = var.disk_pool

  target = {
    format = {
      type = "raw"
    }
  }

  create = {
    content = {
      url = libvirt_cloudinit_disk.this.path
    }
  }
}

# ============================================================
# OS Disk
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

  backing_store = {
    path   = var.base_image_path
    format = {
      type = "qcow2"
    }
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
  running     = true

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
        type = "network"
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
# Data Source for IP Addresses
# ============================================================
data "libvirt_domain_interface_addresses" "this" {
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
  value       = try(data.libvirt_domain_interface_addresses.this.interfaces[0].addrs[0].addr, "N/A")
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