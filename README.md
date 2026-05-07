# Terraform RKE2 Cluster on KVM/QEMU

Infraestructură Terraform pentru crearea a 2 VM-uri KVM pentru cluster RKE2 Kubernetes.

## Structura

```
AstroLumina-Terraform/
├── main.tf                    # Configurația principală Terraform
├── terraform.tfvars         # Variabile
├── tf.sh                   # Helper script (init, apply, destroy, start, stop, ips)
├── modules/
│   └── kvm_vm/           # Modul reutilizabil pentru VM-uri
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── inventory/
    └── hosts.ini.tftpl   # Template Ansible inventory
```

## Specificații VM

| Node | vCPU | RAM | Disk | Rol |
|------|-----|-----|------|-----|
| rke2-cp-01 | 2 | 4 GB | 40 GB | Control Plane (server RKE2) |
| rke2-worker-01 | 2 | 3 GB | 60 GB | Worker (agent RKE2) |

## Cerințe Sistem

### Pachete necesare

```bash
sudo apt-get update
sudo apt-get install -y \
    qemu-system-x86 \
    libvirt-daemon-system \
    libvirt-clients \
    bridge-utils \
    terraform
```

### Verificare KVM/QEMU

```bash
kvm-ok
virt-host-validate
```

### AppArmor (ZorinOS, Ubuntu, etc.)

**Important:** Dacă sistemul are AppArmor activ, libvirtd nu va porni VM-urile. Trebuie oprit AppArmor și restartat libvirtd:

```bash
sudo systemctl stop apparmor
sudo systemctl disable apparmor
sudo systemctl restart libvirtd
```

Fără asta, VM-urile vor fi create dar vor rămâne în stare "shut off".

### Rețeaua virtuală

Trebuie configurată rețeaua `default` în libvirt.tf.sh init face asta automat:

```bash
./tf.sh init
```

Dacă manual:

```bash
sudo virsh net-define <<EOF
<network>
  <name>default</name>
  <forward mode='nat'/>
  <bridge name='virbr0' stp='on' delay='0'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
EOF
sudo virsh net-start default
sudo virsh net-autostart default
```

## Configurare

### 1. Inițializare imagini de bază

Scriptul `tf.sh init` descarcă imaginea Ubuntu 22.04 Cloud Image și o convertește în QCOW2:

```bash
./tf.sh init
```

Aceasta:
- Descarcă `ubuntu-22.04-server-cloudimg-amd64.img` în `/var/lib/libvirt/images/`
- Convertește în `ubuntu.qcow2` (formatul necesar pentru libvirt)
- Setează permisiunile corecte

### 2. Verificare Terraform

```bash
terraform validate
terraform plan
```

### 3. Creare VM-uri

```bash
./tf.sh apply
```

Rulează de două ori (a doua oară pentru a obține IP-urile DHCP).

## Comenzi Helper (tf.sh)

| Comandă | Descriere |
|---------|----------|
| `./tf.sh init` | Descarcă imaginile de bază și inițializează Terraform |
| `./tf.sh apply` | Creează VM-urile |
| `./tf.sh destroy` | Distruge toate VM-urile |
| `./tf.sh start` | Pornește VM-urile |
| `./tf.sh stop` | Oprește graceful VM-urile |
| `./tf.sh force-stop` | Forțează oprirea VM-urilor |
| `./tf.sh ips` | Afișează IP-urile DHCP și starea VM-urilor |
| `./tf.sh status` | Afișează VM-urile care rulează |

## Acces VM-uri

```bash
terraform output ssh_connection_info
```

Sau:

```bash
./tf.sh ips
```

Conectare SSH:

```bash
ssh ubuntu@<IP_VM>
# Parola: ubuntu
```

## Ansible

După crearea VM-urilor, generare inventory:

```bash
terraform output ansible_inventory > inventory/hosts.ini
```

## Troubleshooting

### VM nu pornește

1. Verifică starea:
```bash
virsh list --all
```

2. Dacă sunt "shut off" deși `running = true`:
```bash
sudo systemctl status apparmor
sudo systemctl stop apparmor
sudo systemctl disable apparmor
sudo systemctl restart libvirtd
```

3. Verifică log-urile:
```bash
virsh console rke2-cp-01
```

### Nu apare IP-ul

```bash
./tf.sh ips
# sau
sudo virsh net-dhcp-leases default
```

Apoi rulează terraform apply din nou:

```bash
terraform apply -auto-approve
```

### Provider libvirt error

```bash
sudo systemctl status libvirtd
sudo virt-host-validate
```

## Note

- Rețeaua `default` trebuie să fie configurată în Libvirt
- Parola pentru user-ul `ubuntu` este setată automat la `ubuntu`
- SSH key se configurează în `main.tf`
- La primul boot, VM-urile rulează `apt update && apt upgrade -y`