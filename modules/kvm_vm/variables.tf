variable "vm_name" {
  description = "Numele VM-ului"
  type        = string
}

variable "vcpu" {
  description = "Numărul de procesoare virtuale"
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "Memorie RAM în MB"
  type        = number
  default     = 2048
}

variable "disk_gb" {
  description = "Dimensiunea discului în GB"
  type        = number
  default     = 20
}

variable "ssh_username" {
  description = "Username pentru SSH și sudo"
  type        = string
  default     = "ubuntu"
}

variable "ssh_password" {
  description = "Parola pentru utilizatorul SSH (hash bcrypt sau text clar pentru cloud-init)"
  type        = string
}

variable "ssh_pub_key" {
  description = "Cheia SSH publică pentru autentificare (opțional)"
  type        = string
  default     = ""
}

variable "disk_pool" {
  description = "Pool-ul de stocare"
  type        = string
  default     = "default"
}

variable "tags" {
  description = "Tag-uri pentru VM"
  type        = map(string)
  default     = {}
}

variable "base_image_path" {
  description = "Calea către imaginea de bază QCOW2 (ex: /var/lib/libvirt/images/ubuntu-22.04-server-cloudimg-amd64.img)"
  type        = string
}

variable "cloudinit_user_data" {
  description = "Cloud-init user-data personalizat (opțional)"
  type        = string
  default     = ""
}

variable "network_name" {
  description = "Numele rețelei libvirt"
  type        = string
  default     = "default"
}