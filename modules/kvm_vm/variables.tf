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

variable "mac_address" {
  description = "MAC address pentru IP fix (trebuie să se potrivească cu rezervarea DHCP)"
  type        = string
  default     = ""
}

variable "host_share_path" {
  description = "Host directory shared read-only into the VM via 9p (empty string disables sharing)"
  type        = string
  default     = ""
}

variable "guest_mountpoint" {
  description = "Guest path where the shared directory is mounted"
  type        = string
  default     = "/mnt/k8s"
}

variable "mount_tag" {
  description = "9p mount tag (must match the target dir and the cloud-init mounts entry)"
  type        = string
  default     = "k8s_repo"
}

variable "tailscale_auth_key" {
  description = "Tailscale reusable auth key for automatic tailnet enrollment (empty string disables Tailscale setup)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "tailnet_dns_zone" {
  description = "DNS zone served by dnsmasq on this VM, answered with the node's own Tailscale IP (empty string disables the split-DNS server; requires tailscale_auth_key)"
  type        = string
  default     = ""
}
