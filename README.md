# Terraform RKE2 Cluster on KVM

Infraestructură Terraform pentru crearea a 2 VM-uri KVM pentru cluster RKE2 Kubernetes.

## Structura

```
AstroLumina-Terraform/
├── main.tf                    # Configurația principală Terraform
├── terraform.tfvars         # Variabile
├── modules/
│   └── kvm_vm/           # Modul reutilizabil pentru VM-uri
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── inventory/
│   └── hosts.ini.tftpl   # Template Ansible inventory
└── cloud-init/
    ├── user-data         # cloud-init config ( Ubuntu Server autoinstall)
    └── meta-data
```

## Specificații VM

| Node | vCPU | RAM | Disk | Rol |
|------|-----|-----|------|-----|
| rke2-cp-01 | 2 | 4 GB | 40 GB | Control Plane (server RKE2) |
| rke2-worker-01 | 2 | 3 GB | 60 GB | Worker (agent RKE2) |

## Cerințe

- Terraform >= 1.0
- Provider libvirt (`dmacvicar/libvirt` ~> 0.8)
- KVM/QEMU configurat pe sistem
- Ubuntu 24.04 LTS ISO

## Instalare Provider

```bash
terraform init
```

## Validare

```bash
terraform validate
terraform plan
```

## Creare VM-uri

```bash
terraform apply
```

## Distrugere VM-uri

```bash
terraform destroy
```

## Ansible

După crearea VM-urilor, generare inventory:

```bash
# Cu IP-urile reale, Creează fișierul inventory/hosts.ini
# Setează variabilele și rulează:
terraform output ansible_inventory > inventory/hosts.ini
```

### Playbook RKE2

Folosește playbook-ul pentru instalare RKE2:

```bash
ansible-playbook -i inventory/hosts.ini playbook.yml
```

## Note

- Asigură-te că aibridge-ul de retea `default` configurat în Libvirt
- Adaugă cheia ta SSH în cloud-init/user-data
- Setează o parolă hashed în user-data
- Pentru acces la distanță, folosește URI-ul corect în provider

## Troubleshooting

### VM nu pornește

```bash
# Verifică log-urile
virsh list --all
virsh console rke2-cp-01
```

### Provider libvirt error

```bash
# Verifică că KVM e activ
virt-host-validate
systemctl status libvirtd
```