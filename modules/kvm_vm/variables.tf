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

variable "disk_pool" {
  description = "Pool-ul de stocare"
  type        = string
  default     = "default"
}

variable "tags" {
  description = "Tag-uri pentru VM"
  type        = map(string)
  default    = {}
}

variable "base_image_id" {
  description = "ID-ul imaginii de bază (volume)"
  type        = string
  default     = ""
}

variable "base_image_pool" {
  description = "Pool-ul imaginii de bază"
  type        = string
  default     = "default"
}

variable "cloudinit_iso_path" {
  description = "Calea către cloud-init ISO"
  type        = string
  default     = ""
}

variable "network_id" {
  description = "ID-ul rețelei libvirt"
  type        = string
  default     = ""
}