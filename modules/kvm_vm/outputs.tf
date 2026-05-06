# KVM VM Module - Outputs

output "vm_name" {
  description = "Numele VM-ului"
  value       = var.vm_name
}

output "vcpu" {
  description = "Număr vCPU"
  value       = var.vcpu
}

output "memory_mb" {
  description = "Memorie RAM în MB"
  value       = var.memory_mb
}

output "disk_gb" {
  description = "Dimensiune disk în GB"
  value       = var.disk_gb
}

output "ip_address" {
  description = "Adresa IP a VM-ului"
  value       = libvirt_domain.this.network_interface[0].addresses[0]
}