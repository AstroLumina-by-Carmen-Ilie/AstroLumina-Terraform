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

variable "k8s_repo_host_path" {
  description = "Host path of AstroLumina-Kubernetes shared read-only into all VMs via 9p (null = sibling repo, empty disables sharing)"
  type        = string
  default     = null
}

locals {
  ubuntu_image_path = "/var/lib/libvirt/images/ubuntu-24.04.qcow2"
  k8s_share_path    = var.k8s_repo_host_path != null ? var.k8s_repo_host_path : abspath("${path.module}/../AstroLumina-Kubernetes")
}

# ============================================================
module "rke2_control_plane" {
  source = "./modules/kvm_vm"

  vm_name      = "rke2-cp-01"
  vcpu         = 2
  memory_mb    = 4096
  disk_gb      = 40
  ssh_username = "ubuntu"
  ssh_pub_key  = var.ssh_pub_key
  ssh_password = var.ssh_password
  mac_address  = "52:54:00:a1:b2:c3"

  host_share_path = local.k8s_share_path

  base_image_path = local.ubuntu_image_path
  network_name    = "default"
  disk_pool       = "default"
  running         = true

  tags = {
    role    = "control-plane"
    cluster = "rke2"
  }
}

module "rke2_worker_01" {
  source = "./modules/kvm_vm"

  vm_name      = "rke2-worker-01"
  vcpu         = 2
  memory_mb    = 3072
  disk_gb      = 40
  ssh_username = "ubuntu"
  ssh_pub_key  = var.ssh_pub_key
  ssh_password = var.ssh_password
  mac_address  = "52:54:00:d1:e2:f3"

  host_share_path = local.k8s_share_path

  base_image_path = local.ubuntu_image_path
  network_name    = "default"
  disk_pool       = "default"
  running         = true

  tags = {
    role    = "worker"
    cluster = "rke2"
  }
}

module "rke2_worker_02" {
  source = "./modules/kvm_vm"

  vm_name      = "rke2-worker-02"
  vcpu         = 2
  memory_mb    = 3072
  disk_gb      = 40
  ssh_username = "ubuntu"
  ssh_pub_key  = var.ssh_pub_key
  ssh_password = var.ssh_password
  mac_address  = "52:54:00:aa:bb:cc"

  host_share_path = local.k8s_share_path

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
    worker_1      = module.rke2_worker_01.ip_address
    worker_2      = module.rke2_worker_02.ip_address
  }
}

output "vm_details" {
  description = "Informații VM-uri"
  value = [
    {
      name      = module.rke2_control_plane.vm_name
      vcpu      = module.rke2_control_plane.vcpu
      memory_mb = module.rke2_control_plane.memory_mb
      disk_gb   = module.rke2_control_plane.disk_gb
      role      = "control-plane"
    },
    {
      name      = module.rke2_worker_01.vm_name
      vcpu      = module.rke2_worker_01.vcpu
      memory_mb = module.rke2_worker_01.memory_mb
      disk_gb   = module.rke2_worker_01.disk_gb
      role      = "worker"
    },
    {
      name      = module.rke2_worker_02.vm_name
      vcpu      = module.rke2_worker_02.vcpu
      memory_mb = module.rke2_worker_02.memory_mb
      disk_gb   = module.rke2_worker_02.disk_gb
      role      = "worker"
    }
  ]
}

output "ssh_connection_info" {
  description = "Cum să te conectezi"
  value = [
    "ssh ubuntu@${module.rke2_control_plane.ip_address}",
    "ssh ubuntu@${module.rke2_worker_01.ip_address}",
    "ssh ubuntu@${module.rke2_worker_02.ip_address}"
  ]
}
