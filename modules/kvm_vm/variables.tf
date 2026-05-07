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

variable "network_name" {
  description = "Numele rețelei libvirt"
  type        = string
  default     = "default"
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
  description = "Calea către imaginea de bază QCOW2"
  type        = string
}

variable "ssh_username" {
  description = "Username pentru SSH și sudo"
  type        = string
  default     = "ubuntu"
}

variable "ssh_pub_key" {
  description = "Cheia SSH publică pentru autentificare"
  type        = string
}

variable "ssh_password" {
  description = "Parola pentru user (hashed SHA-512)"
  type        = string
  default     = ""
}

variable "running" {
  description = "Dacă VM-ul pornește automat după creare"
  type        = bool
  default     = false
}