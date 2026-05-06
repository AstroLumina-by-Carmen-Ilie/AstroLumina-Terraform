# Terraform Configuration for RKE2 Cluster on KVM

terraform {
  required_version = ">= 1.0"

  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9"
    }
  }

  provisioner "local-exec" {
    command = "which genisoimage || echo 'genisoimage not found'"
  }
}

provider "libvirt" {
}

# ============================================================
# Variables
# ============================================================
variable "password_hash" {
  description = "SHA-512 hashed password"
  type        = string
  sensitive   = true
}

variable "ssh_pub_key" {
  description = "SSH public key for access"
  type        = string
  default     = ""
}

# ============================================================
# Get Network ID for default network
# ============================================================
data "libvirt_network" "default" {
  name = "default"
}

# ============================================================
# Base Image Volume (Ubuntu 22.04 LTS)
# ============================================================
resource "libvirt_volume" "ubuntu_base" {
  name   = "ubuntu-22.04-base"
  pool   = "default"
  format = "qcow2"
  source = "/var/lib/libvirt/images/ubuntu-22.04-server-cloudimg-amd64.img"
}

# ============================================================
# Cloud-Init ISO for Control Plane
# ============================================================
resource "null_resource" "cloudinit_cp" {
  triggers = {
    password_hash = var.password_hash
    hostname      = "rke2-cp-01"
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      HOST="rke2-cp-01"
      mkdir -p /tmp/cloud-init-cp
      
      cat > /tmp/cloud-init-cp/user-data << USERDATA
#cloud-config
autoinstall:
  version: 1
  locale: en_US.UTF-8
  keyboard:
    layout: us
  identity:
    hostname: rke2-cp-01
    password: "${password_hash}"
    name: ubuntu
  ssh:
    install-server: true
    allow-pw: true
  storage:
    layout:
      name: LVM
  packages:
    - openssh-server
    - curl
    - wget
    - git
    - vim
    - net-tools
    - jq
    - ca-certificates
  late-commands:
    - echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/ubuntu
USERDATA

      cat > /tmp/cloud-init-cp/meta-data << METADATA
instance-id: rke2-cp-01
local-hostname: rke2-cp-01
METADATA

      genisoimage -o /tmp/cloud-init-cp.iso -r -V "cidata" /tmp/cloud-init-cp/
      echo "/tmp/cloud-init-cp.iso"
    EOT

    interpreter = ["bash", "-c"]
    vars = {
      password_hash = var.password_hash
    }
  }
}

# ============================================================
# Cloud-Init ISO for Worker
# ============================================================
resource "null_resource" "cloudinit_worker" {
  triggers = {
    password_hash = var.password_hash
    hostname      = "rke2-worker-01"
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      mkdir -p /tmp/cloud-init-worker
      
      cat > /tmp/cloud-init-worker/user-data << USERDATA
#cloud-config
autoinstall:
  version: 1
  locale: en_US.UTF-8
  keyboard:
    layout: us
  identity:
    hostname: rke2-worker-01
    password: "${password_hash}"
    name: ubuntu
  ssh:
    install-server: true
    allow-pw: true
  storage:
    layout:
      name: LVM
  packages:
    - openssh-server
    - curl
    - wget
    - git
    - vim
    - net-tools
    - jq
    - ca-certificates
  late-commands:
    - echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/ubuntu
USERDATA

      cat > /tmp/cloud-init-worker/meta-data << METADATA
instance-id: rke2-worker-01
local-hostname: rke2-worker-01
METADATA

      genisoimage -o /tmp/cloud-init-worker.iso -r -V "cidata" /tmp/cloud-init-worker/
      echo "/tmp/cloud-init-worker.iso"
    EOT

    interpreter = ["bash", "-c"]
    vars = {
      password_hash = var.password_hash
    }
  }
}

locals {
  cloudinit_cp_path     = trimspace(null_resource.cloudinit_cp.stdout)
  cloudinit_worker_path = trimspace(null_resource.cloudinit_worker.stdout)
}

# ============================================================
# Control Plane Node (RKE2) - 4GB RAM, 2 vCPU
# ============================================================
module "rke2_control_plane" {
  source = "./modules/kvm_vm"

  vm_name      = "rke2-cp-01"
  vcpu         = 2
  memory_mb    = 4096
  disk_gb      = 40
  ssh_username = "ubuntu"

  base_image_id      = libvirt_volume.ubuntu_base.id
  base_image_pool    = "default"
  cloudinit_iso_path = local.cloudinit_cp_path
  network_id         = data.libvirt_network.default.id
  disk_pool          = "default"

  tags = {
    role    = "control-plane"
    cluster = "rke2"
  }
}

# ============================================================
# Worker Node - 3GB RAM, 2 vCPU
# ============================================================
module "rke2_worker" {
  source = "./modules/kvm_vm"

  vm_name      = "rke2-worker-01"
  vcpu         = 2
  memory_mb    = 3072
  disk_gb      = 60
  ssh_username = "ubuntu"

  base_image_id      = libvirt_volume.ubuntu_base.id
  base_image_pool    = "default"
  cloudinit_iso_path = local.cloudinit_worker_path
  network_id         = data.libvirt_network.default.id
  disk_pool          = "default"

  tags = {
    role    = "worker"
    cluster = "rke2"
  }
}

# ============================================================
# Outputs
# ============================================================
output "vm_ips" {
  description = "IP-urile VM-urilor"
  value = {
    control_plane = module.rke2_control_plane.ip_address
    worker        = module.rke2_worker.ip_address
  }
}

output "vm_details" {
  description = "Informații VM-uri"
  value = {
    control_plane = {
      name      = module.rke2_control_plane.vm_name
      vcpu      = module.rke2_control_plane.vcpu
      memory_mb = module.rke2_control_plane.memory_mb
      disk_gb   = module.rke2_control_plane.disk_gb
    }
    worker = {
      name      = module.rke2_worker.vm_name
      vcpu      = module.rke2_worker.vcpu
      memory_mb = module.rke2_worker.memory_mb
      disk_gb   = module.rke2_worker.disk_gb
    }
  }
}

output "ssh_connection_info" {
  description = "Cum să te conectezi"
  value       = <<-EOF
ssh ubuntu@<CP_IP>
ssh ubuntu@<WORKER_IP>
EOF
}