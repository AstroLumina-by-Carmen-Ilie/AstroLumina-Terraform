# Terraform RKE2 Cluster on KVM/QEMU

Terraform infrastructure for creating 2 KVM VMs for the RKE2 Kubernetes cluster.

## Structure

```
AstroLumina-Terraform/
├── main.tf                    # Main Terraform configuration
├── terraform.tfvars         # Variables
├── tf.sh                   # Helper script (init, apply, destroy, start, stop, ips)
├── configs/
│   └── network-default.xml   # libvirt network configuration (KVM/QEMU only)
├── modules/
│   └── kvm_vm/           # Reusable VM module
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── inventory/
    └── hosts.ini.tftpl   # Ansible inventory template
```

## VM Specifications

| Node           | vCPU | RAM  | Disk  | Role                        |
| -------------- | ---- | ---- | ----- | --------------------------- |
| rke2-cp-01     | 2    | 4 GB | 40 GB | Control Plane (RKE2 server) |
| rke2-worker-01 | 2    | 3 GB | 60 GB | Worker (RKE2 agent)         |

## System Requirements (KVM/QEMU)

### Required packages

```bash
sudo apt-get update
sudo apt-get install -y \
    qemu-system-x86 \
    libvirt-daemon-system \
    libvirt-clients \
    bridge-utils \
    terraform
```

### KVM/QEMU check

```bash
kvm-ok
virt-host-validate
```

### AppArmor (KVM/QEMU - ZorinOS, Ubuntu, etc.)

**KVM/QEMU note:** if the system has AppArmor enabled, libvirtd will not start the VMs:

```bash
sudo systemctl stop apparmor
sudo systemctl restart libvirtd
```

### Virtual network (KVM/QEMU only)

**KVM/QEMU specific:** the virtual network and fixed IPs are configured in libvirt.

Configuration file: `configs/network-default.xml`

```bash
./tf.sh init
```

If done manually:

```bash
sudo virsh net-define configs/network-default.xml
sudo virsh net-start default
sudo virsh net-autostart default
```

### Storage Pool (KVM/QEMU only)

**KVM/QEMU specific:** KVM ships with a preconfigured `default` storage pool:

```
/var/lib/libvirt/images/
```

Base images (ubuntu.qcow2) go here and VM disks are created here. No additional configuration needed.

## Configuration

### 1. Base image initialization

The `tf.sh init` script downloads the Ubuntu 22.04 Cloud Image and converts it to QCOW2:

```bash
./tf.sh init
```

This:

- Downloads `ubuntu-22.04-server-cloudimg-amd64.img` to `/var/lib/libvirt/images/`
- Converts it to `ubuntu.qcow2` (the format required by libvirt)
- Sets the correct permissions

### 2. Terraform check

```bash
terraform validate
terraform plan
```

### 3. Create VMs

```bash
./tf.sh apply
```

Run it twice (the second run picks up the DHCP IPs).

## Helper commands (tf.sh)

| Command            | Description                                                              |
| ------------------ | ------------------------------------------------------------------------ |
| `./tf.sh init`     | Downloads base images, configures the network and initializes Terraform |
| `./tf.sh apply`    | Creates the VMs with fixed IPs (192.168.122.10, 192.168.122.11)         |
| `./tf.sh destroy`  | Destroys all VMs                                                        |
| `./tf.sh start`    | Starts the VMs                                                          |
| `./tf.sh stop`     | Gracefully stops the VMs                                                |
| `./tf.sh force-stop` | Force-stops the VMs                                                   |
| `./tf.sh ips`      | Shows DHCP IPs and VM status                                            |
| `./tf.sh status`   | Shows the running VMs                                                   |

## Fixed IPs (KVM/QEMU only)

**KVM/QEMU specific:** the VMs get fixed IPs via DHCP reservations defined in `configs/network-default.xml`:

| VM             | MAC Address       | Fixed IP       |
| -------------- | ----------------- | -------------- |
| rke2-cp-01     | 52:54:00:a1:b2:c3 | 192.168.122.10 |
| rke2-worker-01 | 52:54:00:d1:e2:f3 | 192.168.122.11 |

Configured in `configs/network-default.xml`:

```xml
<dhcp>
  <range start='192.168.122.12' end='192.168.122.254'/>
  <host mac='52:54:00:a1:b2:c3' ip='192.168.122.10'/>
  <host mac='52:54:00:d1:e2:f3' ip='192.168.122.11'/>
</dhcp>
```

## VM access

```bash
terraform output ssh_connection_info
```

Or:

```bash
./tf.sh ips
```

SSH connection:

```bash
ssh ubuntu@<VM_IP>
# Password: ubuntu
```

## Kubernetes repo shared with the VMs (9p)

The `AstroLumina-Kubernetes` directory on the host is automatically shared,
read-only, with all 3 VMs via 9p filesystem passthrough. After boot,
the repo is available on any VM at:

```bash
ls /mnt/k8s/development/
kubectl apply -k /mnt/k8s/development/
```

How it works:

- `main.tf` — the `k8s_repo_host_path` variable (`null` = the sibling
  `../AstroLumina-Kubernetes` repo, empty string = disables sharing). Can be
  overridden with `-var='k8s_repo_host_path=/other/path'` or an empty `"..."`.
- `modules/kvm_vm` — the `filesystems` block in `libvirt_domain` (host-side
  `mount.dir` source, `k8s_repo` tag, `passthrough`, `read_only`) +
  the `mounts` entry in cloud-init (`9p`, `trans=virtio,version=9p2000.L,ro`).
- The tag in `target.dir` must stay identical to the one in cloud-init,
  otherwise mounting fails at boot.

Host requirements (otherwise the VM fails to start or the mount is missing):

1. qemu must be able to read the path. With AppArmor stopped (see the section
   above) plus `security_driver = "none"` in `/etc/libvirt/qemu.conf`
   (lab only), nothing else is needed. With default settings,
   grant rights: `setfacl -R -m u:libvirt-qemu:rX <repo>` and `u:libvirt-qemu:--x`
   on every parent directory down to `/`.
2. The directory must exist at `terraform apply` time, otherwise libvirt refuses
   to define the domain.

Check on the VM:

```bash
mount | grep /mnt/k8s   # 9p, ro
touch /mnt/k8s/probe && echo PROBLEM || echo "read-only OK"
```

## Troubleshooting

### VM does not start

1. Check the state:

```bash
virsh list --all
```

2. If they are "shut off" even though `running = true`:

```bash
sudo systemctl status apparmor
sudo systemctl stop apparmor
sudo systemctl restart libvirtd
```

3. Check the logs:

```bash
virsh console rke2-cp-01
```

### IP does not show up

```bash
./tf.sh ips
# or
sudo virsh net-dhcp-leases default
```

Then run terraform apply again:

```bash
terraform apply -auto-approve
```

### Provider libvirt error

```bash
sudo systemctl status libvirtd
sudo virt-host-validate
```

## Notes

- The `default` network must be configured in Libvirt
- The password for the `ubuntu` user is automatically set to `ubuntu`
- The SSH key is configured in `main.tf`
- On first boot, the VMs run `apt update && apt upgrade -y`
