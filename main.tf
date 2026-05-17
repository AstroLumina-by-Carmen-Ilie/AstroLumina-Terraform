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

variable "ssh_password" {
  description = "Password for user ubuntu (plain text - will be hashed by cloud-init)"
  type        = string
  default     = "ubuntu"
}

locals {
  ubuntu_image_path = "/var/lib/libvirt/images/ubuntu-24.04.qcow2"
}

# ============================================================
module "rke2_control_plane" {
  source = "./modules/kvm_vm"

  vm_name       = "rke2-cp-01"
  vcpu          = 2
  memory_mb     = 4096
  disk_gb       = 40
  ssh_username = "ubuntu"
  ssh_pub_key  = var.ssh_pub_key
  ssh_password = var.ssh_password
  mac_address  = "52:54:00:a1:b2:c3"

  base_image_path = local.ubuntu_image_path
  network_name    = "default"
  disk_pool       = "default"
  running         = true

  tags = {
    role    = "control-plane"
    cluster = "rke2"
  }
}

module "rke2_worker" {
  source = "./modules/kvm_vm"

  vm_name       = "rke2-worker-01"
  vcpu          = 2
  memory_mb     = 4096
  disk_gb       = 40
  ssh_username = "ubuntu"
  ssh_pub_key  = var.ssh_pub_key
  ssh_password = var.ssh_password
  mac_address  = "52:54:00:d1:e2:f3"

  base_image_path = local.ubuntu_image_path
  network_name    = "default"
  disk_pool       = "default"
  running         = true

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
  value = [
    "ssh ubuntu@${module.rke2_control_plane.ip_address}",
    "ssh ubuntu@${module.rke2_worker.ip_address}"
  ]
}
