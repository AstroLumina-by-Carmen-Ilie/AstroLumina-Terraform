#!/bin/bash

# ============================================================
# Terraform KVM/QEMU Helper Script
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# VM names
VM_CP="rke2-cp-01"
VM_WORKER="rke2-worker-01"

# ============================================================
# Check for required packages
# ============================================================
check_packages() {
    local missing=()
    for pkg in qemu-system-x86 libvirt-daemon-system bridge-utils; do
        if ! dpkg -l | grep -q "^ii.*$pkg"; then
            missing+=("$pkg")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Missing packages: ${missing[*]}"
        echo "Install with: sudo apt-get install -y ${missing[*]}"
    fi
    
    if ! command -v terraform &> /dev/null; then
        echo "Terraform not found"
    else
        terraform -v | head -1
    fi
}

# ============================================================
# Download and convert base images (if not present)
# ============================================================
init_images() {
    libvirt_img_path="/var/lib/libvirt/images"
    base_image="${libvirt_img_path}/ubuntu-22.04-server-cloudimg-amd64.img"
    base_image_url="https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
    
    if [[ ! -f "$base_image" ]]; then
        echo "Base image not found at $base_image"
        echo "Downloading..."
        sudo wget -O "$base_image" "$base_image_url"
        sudo chmod 644 "$base_image"
        sudo chown libvirt-qemu:kvm "$base_image"
        echo "...Download complete"
    fi
    
    qcow2_image="${libvirt_img_path}/ubuntu.qcow2"
    if [[ ! -f "$qcow2_image" ]]; then
        echo "Ubuntu QCOW2 image not found at $qcow2_image"
        echo "Converting IMG to QCOW2..."
        sudo qemu-img convert -O qcow2 "$base_image" "$qcow2_image"
        sudo chmod 644 "$qcow2_image"
        sudo chown libvirt-qemu:kvm "$qcow2_image"
        echo "...Done"
    fi
}

# ============================================================
# Recreate network (for new MACs/IPs)
# ============================================================
recreate_network() {
    echo "Recreating libvirt network..."
    sudo virsh net-destroy default 2>/dev/null || true
    sudo virsh net-undefine default 2>/dev/null || true
    sudo virsh net-define "$SCRIPT_DIR/configs/network-default.xml"
    sudo virsh net-start default
    sudo virsh net-autostart default
    echo "Network recreated"
}

# ============================================================
# Start all VMs
# ============================================================
start_vms() {
    echo "Starting VMs..."
    sudo virsh start "$VM_CP"
    sudo virsh start "$VM_WORKER"
    echo "VMs started"
}

# ============================================================
# Stop all VMs (graceful shutdown)
# ============================================================
stop_vms() {
    echo "Stopping VMs (graceful shutdown)..."
    sudo virsh shutdown "$VM_CP"
    sudo virsh shutdown "$VM_WORKER"
    
    # Wait for shutdown
    for vm in "$VM_CP" "$VM_WORKER"; do
        echo "Waiting for $vm to shutdown..."
        for i in {1..30}; do
            if ! sudo virsh list | grep -q "$vm"; then
                echo "$vm stopped"
                break
            fi
            sleep 1
        done
    done
}

# ============================================================
# Force stop VMs (if graceful fails)
# ============================================================
force_stop_vms() {
    echo "Force stopping VMs..."
    sudo virsh destroy "$VM_CP"
    sudo virsh destroy "$VM_WORKER"
    echo "VMs destroyed"
}

# ============================================================
# Get IPs from DHCP leases
# ============================================================
get_ips() {
    echo "Current DHCP leases:"
    sudo virsh net-dhcp-leases default
    echo ""
    echo "VM status:"
    sudo virsh list --all
}

# ============================================================
# Main case statement
# ============================================================
ensure_network() {
    echo "Ensuring libvirt network..."
    if sudo virsh net-info default 2>/dev/null | grep -q "Active:.*yes"; then
        echo "Network already active"
    else
        sudo virsh net-start default
        sudo virsh net-autostart default
    fi
}

case $1 in
    "init")
        check_packages
        ensure_network
        init_images
		terraform init
        ;;
    "apply")
        terraform apply -auto-approve
        sleep 15
        terraform apply -auto-approve
        ;;
    "destroy")
        terraform destroy -auto-approve
        ;;
    "start")
        start_vms
        ;;
    "stop")
        stop_vms
        ;;
    "force-stop")
        force_stop_vms
        ;;
    "ips")
        get_ips
        ;;
    "recreate-network")
        recreate_network
        ;;
    "status")
        sudo virsh list --all
        ;;
    *)
        echo "Terraform KVM/QEMU Helper"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
echo "Commands:"
        echo "  init               - Download base images and initialize Terraform"
        echo "  apply              - Create VMs with terraform apply (runs twice for IPs)"
        echo "  destroy           - Destroy all VMs"
        echo "  start             - Start all VMs"
        echo "  stop              - Graceful shutdown all VMs"
        echo "  force-stop        - Force stop (destroy) all VMs"
        echo "  ips               - Show DHCP leases and VM status"
        echo "  status            - Show running VMs"
        echo "  recreate-network  - Recreate network (for new MACs)"
        echo ""

        echo "Examples:"
        echo "  $0 init               # First time setup"
        echo "  $0 apply              # Create VMs"
        echo "  $0 ips               # Get VM IPs"
        echo "  $0 recreate-network # Recreate network with new DHCP reservations"
        return 1
        ;;
esac