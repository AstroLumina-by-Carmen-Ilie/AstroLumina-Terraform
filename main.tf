# Terraform Configuration for RKE2 Cluster on KVM

terraform {
  required_version = ">= 1.0"

  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9"
    }
  }
}

provider "libvirt" {
}

# ============================================================
# Variables
# ============================================================
variable "ssh_pub_key" {
  description = "SSH public key for access"
  type        = string
  default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOQIgh+H2AXLQyqOm5uVT0r0FhT9iAnF6k9d7UjrxUh5 daniel.catalin.pirvu@gmail.com"
}

# ============================================================
# Base Image Volume (Ubuntu 22.04 LTS)
# ============================================================
resource "libvirt_volume" "ubuntu_base" {
  name = "ubuntu-22.04-base"
  pool = "terraform-pool"

  target = {
    format = {
      type = "qcow2"
    }
  }

  create = {
    content = {
      url = "file:///home/daniel/libvirt-images/ubuntu-22.04-server-cloudimg-amd64.img"
    }
  }
}

locals {
  base_image_path = libvirt_volume.ubuntu_base.path
  ssh_password    = "$6$v1t7CQ/6dLluvzuU$p/fj5WYkimzoFTkLl141mHChFnKXOTvy2QbYXry.0cPwQ0jtYs4YnnwD6lV50qxio7dmgFa1xm/k74uPksJIf."
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
  ssh_password = local.ssh_password
  ssh_pub_key  = var.ssh_pub_key

  base_image_path = local.base_image_path
  network_name    = "default"
  disk_pool       = "terraform-pool"

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
  ssh_password = local.ssh_password
  ssh_pub_key  = var.ssh_pub_key

  base_image_path = local.base_image_path
  network_name    = "default"
  disk_pool       = "terraform-pool"

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