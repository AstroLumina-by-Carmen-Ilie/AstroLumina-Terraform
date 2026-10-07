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

  user_data = <<-EOF
#cloud-config
users:
  - name: ${var.ssh_username}
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin, sudo
    home: /home/${var.ssh_username}
    shell: /bin/bash
    ssh_authorized_keys:
      - ${var.ssh_pub_key}
%{if var.ssh_password != ""}
    passwd: "${var.ssh_password}"
%{endif}

ssh_pwauth: ${var.ssh_password != "" ? "true" : "false"}
%{if var.host_share_path != ""}
bootcmd:
  - modprobe 9pnet_virtio
mounts:
  - ["${var.mount_tag}", "${var.guest_mountpoint}", "9p", "trans=virtio,version=9p2000.L,ro", "0", "0"]
%{endif}

packages:
  - openssh-server
  - curl
  - wget
  - git
  - vim
  - net-tools
  - jq
  - ca-certificates
%{if var.tailscale_auth_key != "" && var.tailnet_dns_zone != ""}
  - dnsmasq
%{endif}

%{if var.tailscale_auth_key != "" && var.tailnet_dns_zone != ""}
# Split-DNS helper: serves <zone> -> this node's own Tailscale IP.
# The IP is resolved at first boot (after 'tailscale up'), so VM rebuilds
# that get a new tailnet IP keep working with no manual DNS edits.
write_files:
  - path: /etc/dnsmasq.d/tailnet-base.conf
    permissions: '0644'
    content: |
      interface=tailscale0
      bind-interfaces
  - path: /usr/local/sbin/tailnet-dns-apply.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      # Wait for the node's Tailscale IPv4, then point the zone at it.
      ZONE="$1"
      TS_IP=""
      for _ in $(seq 1 60); do
        TS_IP=$(tailscale ip -4 2>/dev/null | head -n 1)
        case "$TS_IP" in 100.*) break ;; *) TS_IP="" ;; esac
        sleep 5
      done
      if [ -z "$TS_IP" ]; then
        echo "tailnet-dns-apply: no Tailscale IPv4 yet, giving up" >&2
        exit 1
      fi
      echo "address=/$${ZONE}/$${TS_IP}" > /etc/dnsmasq.d/tailnet-zone.conf
      systemctl enable --now dnsmasq
      systemctl restart dnsmasq
%{endif}

runcmd:
   - echo '${var.ssh_username}:${var.ssh_password}' | chpasswd
   - systemctl enable ssh
   - systemctl start ssh
   - apt update && apt upgrade -y
%{if var.tailscale_auth_key != ""}
   # Install Tailscale and join the tailnet with a stable hostname (survives VM rebuilds)
   - curl -fsSL https://tailscale.com/install.sh | sh
   - tailscale up --authkey='${var.tailscale_auth_key}' --hostname=${var.vm_name} --accept-dns
%{endif}
%{if var.tailscale_auth_key != "" && var.tailnet_dns_zone != ""}
   # Point the split-DNS zone at this node's current Tailscale IP
   - /usr/local/sbin/tailnet-dns-apply.sh ${var.tailnet_dns_zone}
%{endif}
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

  cpu = {
    mode = "host-passthrough"
  }

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
        mac = var.mac_address != "" ? { address = var.mac_address } : null
      }
    ]

    # Optional 9p share of a host directory (e.g. the Kubernetes manifests
    # repo). The guest mount tag in target.dir must match the cloud-init
    # mounts entry above. Empty list when sharing is disabled.
    filesystems = var.host_share_path != "" ? [
      {
        source = {
          mount = { dir = var.host_share_path }
        }
        target      = { dir = var.mount_tag }
        access_mode = "passthrough"
        read_only   = true
      }
    ] : []

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
  count  = var.running ? 1 : 0
  domain = var.vm_name
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
