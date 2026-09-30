# Terraform RKE2 Cluster on KVM/QEMU

Infraestructură Terraform pentru crearea a 2 VM-uri KVM pentru cluster RKE2 Kubernetes.

## Structura

```
AstroLumina-Terraform/
├── main.tf                    # Configurația principală Terraform
├── terraform.tfvars         # Variabile
├── tf.sh                   # Helper script (init, apply, destroy, start, stop, ips)
├── configs/
│   └── network-default.xml   # Configurație rețea libvirt (KVM/QEMU only)
├── modules/
│   └── kvm_vm/           # Modul reutilizabil pentru VM-uri
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── inventory/
    └── hosts.ini.tftpl   # Template Ansible inventory
```

## Specificații VM

| Node           | vCPU | RAM  | Disk  | Rol                         |
| -------------- | ---- | ---- | ----- | --------------------------- |
| rke2-cp-01     | 2    | 4 GB | 40 GB | Control Plane (server RKE2) |
| rke2-worker-01 | 2    | 3 GB | 60 GB | Worker (agent RKE2)         |

## Cerințe Sistem (KVM/QEMU)

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

### AppArmor (KVM/QEMU - ZorinOS, Ubuntu, etc.)

**Notă KVM/QEMU:** Dacă sistemul are AppArmor activ, libvirtd nu va porni VM-urile:

```bash
sudo systemctl stop apparmor
sudo systemctl restart libvirtd
```

### Rețeaua virtuală (KVM/QEMU only)

**Specific KVM/QEMU:** Rețeaua virtuală și IP-urile fixe sunt configurate în libvirt.

Fișier de configurare: `configs/network-default.xml`

```bash
./tf.sh init
```

Dacă manual:

```bash
sudo virsh net-define configs/network-default.xml
sudo virsh net-start default
sudo virsh net-autostart default
```

### Storage Pool (KVM/QEMU only)

**Specific KVM/QEMU:** KVM vine cu un storage pool `default` preconfigurat:

```
/var/lib/libvirt/images/
```

Aici se pun imaginile de bază (ubuntu.qcow2) și aici se creează disk-urile VM-urilor. Nu necesită configurare suplimentară.

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

| Comandă              | Descriere                                                                   |
| -------------------- | --------------------------------------------------------------------------- |
| `./tf.sh init`       | Descarcă imaginile de bază, configurează rețeaua și inițializează Terraform |
| `./tf.sh apply`      | Creează VM-urile cu IP-uri fixe (192.168.122.10, 192.168.122.11)            |
| `./tf.sh destroy`    | Distruge toate VM-urile                                                     |
| `./tf.sh start`      | Pornește VM-urile                                                           |
| `./tf.sh stop`       | Oprește graceful VM-urile                                                   |
| `./tf.sh force-stop` | Forțează oprirea VM-urilor                                                  |
| `./tf.sh ips`        | Afișează IP-urile DHCP și starea VM-urilor                                  |
| `./tf.sh status`     | Afișează VM-urile care rulează                                              |

## IP-uri Fixe (KVM/QEMU only)

**Specific KVM/QEMU:** VM-urile primesc IP-uri fixe prin rezervări DHCP definite în `configs/network-default.xml`:

| VM             | MAC Address       | IP Fix         |
| -------------- | ----------------- | -------------- |
| rke2-cp-01     | 52:54:00:a1:b2:c3 | 192.168.122.10 |
| rke2-worker-01 | 52:54:00:d1:e2:f3 | 192.168.122.11 |

Configurate în `configs/network-default.xml`:

```xml
<dhcp>
  <range start='192.168.122.12' end='192.168.122.254'/>
  <host mac='52:54:00:a1:b2:c3' ip='192.168.122.10'/>
  <host mac='52:54:00:d1:e2:f3' ip='192.168.122.11'/>
</dhcp>
```

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

## Repo Kubernetes partajat pe VM-uri (9p)

Directorul `AstroLumina-Kubernetes` de pe host este partajat automat,
read-only, în toate cele 3 VM-uri via 9p filesystem passthrough. După boot,
pe orice VM găsești repo-ul la:

```bash
ls /mnt/k8s/development/
kubectl apply -k /mnt/k8s/development/
```

Cum funcționează:

- `main.tf` — variabila `k8s_repo_host_path` (`null` = repo-ul sibling
  `../AstroLumina-Kubernetes`, șir gol = dezactivează partajarea). Se poate
  suprascrie cu `-var='k8s_repo_host_path=/alt/calea'` sau `="..."` gol.
- `modules/kvm_vm` — blocul `filesystems` din `libvirt_domain` (sursă
  `mount.dir` pe host, tag `k8s_repo`, `passthrough`, `read_only`) +
  intrarea `mounts` din cloud-init (`9p`, `trans=virtio,version=9p2000.L,ro`).
- Tag-ul din `target.dir` trebuie să rămână identic cu cel din cloud-init,
  altfel montarea eșuează la boot.

Cerințe pe host (altfel VM-ul nu pornește sau mount-ul lipsește):

1. qemu trebuie să poată citi calea. Cu AppArmor oprit (vezi secțiunea de
   mai sus) plus `security_driver = "none"` în `/etc/libvirt/qemu.conf`
   (doar pentru lab) nu e nevoie de nimic altceva. Cu setările implicite,
   dă-i drepturi: `setfacl -R -m u:libvirt-qemu:rX <repo>` și `u:libvirt-qemu:--x`
   pe fiecare director părinte până la `/`.
2. Directorul trebuie să existe la `terraform apply`, altfel libvirt refuză
   definirea domeniului.

Verificare pe VM:

```bash
mount | grep /mnt/k8s   # 9p, ro
touch /mnt/k8s/probe && echo PROBLEM || echo "read-only OK"
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
