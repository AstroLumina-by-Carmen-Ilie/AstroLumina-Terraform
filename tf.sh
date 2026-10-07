#!/bin/bash

# ============================================================
# Terraform KVM/QEMU Helper Script
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# VM names
VM_CP="rke2-cp-01"
VM_WORKER="rke2-worker-01"
VM_WORKER2="rke2-worker-02"

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
    ubuntu_version="24.04"
    libvirt_img_path="/var/lib/libvirt/images"
    base_image="${libvirt_img_path}/ubuntu-${ubuntu_version}-server-cloudimg-amd64.img"
    base_image_url="https://cloud-images.ubuntu.com/releases/${ubuntu_version}/release/ubuntu-${ubuntu_version}-server-cloudimg-amd64.img"
    
    if [[ ! -f "$base_image" ]]; then
        echo "Base image not found at $base_image"
        echo "Downloading..."
        sudo wget -O "$base_image" "$base_image_url"
        sudo chmod 644 "$base_image"
        sudo chown libvirt-qemu:kvm "$base_image"
        echo "...Download complete"
    fi
    
    qcow2_image="${libvirt_img_path}/ubuntu-${ubuntu_version}.qcow2"
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
    for vm in "$VM_CP" "$VM_WORKER" "$VM_WORKER2"; do
        sudo virsh start "$vm"
    done
    echo "VMs started"
}

# ============================================================
# Stop all VMs (graceful shutdown)
# ============================================================
stop_vms() {
    echo "Stopping VMs (graceful shutdown)..."
    for vm in "$VM_CP" "$VM_WORKER" "$VM_WORKER2"; do
        sudo virsh shutdown "$vm"
    done
    
    # Wait for shutdown
    for vm in "$VM_CP" "$VM_WORKER" "$VM_WORKER2"; do
        echo "Waiting for $vm to shutdown..."
        for _ in {1..60}; do
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
    for vm in "$VM_CP" "$VM_WORKER" "$VM_WORKER2"; do
        sudo virsh destroy "$vm"
    done
    echo "VMs destroyed"
}

# VM network identities (must match configs/network-default.xml reservations)
VM_CP_MAC="52:54:00:a1:b2:c3"
VM_WORKER_MAC="52:54:00:d1:e2:f3"
VM_WORKER2_MAC="52:54:00:aa:bb:cc"
VM_CP_IP="192.168.122.10"
VM_WORKER_IP="192.168.122.11"
VM_WORKER2_IP="192.168.122.12"
SSH_USER="ubuntu"
WAIT_INTERVAL=10
WAIT_TIMEOUT_DEFAULT=600

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

# Resolve current IP for a MAC from DHCP leases, fallback to static reservation
vm_ip() {
    local mac="$1"
    local fallback="$2"
    local leased
    leased=$(sudo virsh net-dhcp-leases default 2>/dev/null | grep -i "$mac" | grep -oE '192\.168\.122\.[0-9]+' | head -1)
    if [[ -n "$leased" ]]; then
        echo "$leased"
    else
        echo "$fallback"
    fi
}

ssh_vm() {
    local ip="$1"
    shift
    ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "${SSH_USER}@${ip}" "$@"
}

# Wait for a single VM: cloud-init done + tailscale up (100.x IP). Returns 0 on success.
wait_one_vm() {
    local name="$1"
    local ip="$2"
    local deadline="$3"
    local ci ts_ip now

    echo "==> ${name} (${ip}): waiting for cloud-init + tailscale..."
    while true; do
        now=$(date +%s)
        if (( now >= deadline )); then
            echo "TIMEOUT: ${name} did not become ready in time."
            return 1
        fi
        if ! ssh_vm "$ip" "true" 2>/dev/null; then
            echo "    ... SSH unavailable, retrying in ${WAIT_INTERVAL}s"
            sleep "$WAIT_INTERVAL"
            continue
        fi
        ci=$(ssh_vm "$ip" "cloud-init status 2>/dev/null" || true)
        if ! echo "$ci" | grep -q ": done"; then
            echo "    ... cloud-init: ${ci:-unknown}"
            sleep "$WAIT_INTERVAL"
            continue
        fi
        ts_ip=$(ssh_vm "$ip" "tailscale ip -4 2>/dev/null" | head -1 || true)
        if echo "$ts_ip" | grep -qE '^100\.'; then
            echo "OK: ${name} cloud-init done, tailscale ${ts_ip}"
            return 0
        fi
        echo "    ... cloud-init done, tailscale not up yet"
        sleep "$WAIT_INTERVAL"
    done
}

# Split-DNS zone served by the worker-01 dnsmasq (must match main.tf)
TAILNET_DNS_ZONE="k8s.astrolumina.ro"
# Tailscale API token for split-DNS updates (generate at
# https://login.tailscale.com/admin/settings/keys, stored in .env, never committed)
TAILSCALE_API_TOKEN="${TAILSCALE_API_TOKEN:-${tailscale_api_token:-}}"
TAILSCALE_TAILNET="${TAILSCALE_TAILNET:--}"
# Tailscale join credentials for Terraform (forwarded as TF_VAR_* in "apply").
# Read from the OS environment at runtime, never committed.
tailscale_auth_key="${tailscale_auth_key:-${TAILSCALE_AUTH_KEY:-}}"
tailscale_suffix="${tailscale_suffix:-${TAILSCALE_SUFFIX:-}}"

# Point the tailnet split-DNS zone at worker-01's current Tailscale IP.
# Makes production.k8s.astrolumina.ro work from any tailnet device without
# manual edits after VM rebuilds (which may change the 100.x IP).
# Usage: dns_sync
dns_sync() {
    local lan_ip ts_ip current merged

    lan_ip=$(vm_ip "$VM_WORKER_MAC" "$VM_WORKER_IP")
    ts_ip=$(ssh_vm "$lan_ip" "tailscale ip -4 2>/dev/null" | head -1)
    if ! echo "$ts_ip" | grep -qE '^100\.'; then
        echo "dns-sync: worker-01 has no Tailscale IP yet (got '${ts_ip:-none}'). Run '$0 wait' first."
        return 1
    fi
    echo "dns-sync: worker-01 tailscale IP is ${ts_ip}"

    # Safety net: ensure the on-VM dnsmasq zone points at the live IP
    # (cloud-init already does this at first boot via tailnet-dns-apply.sh).
    ssh_vm "$lan_ip" "echo 'address=/${TAILNET_DNS_ZONE}/${ts_ip}' | sudo tee /etc/dnsmasq.d/tailnet-zone.conf >/dev/null && sudo systemctl restart dnsmasq" || {
        echo "dns-sync: failed to refresh dnsmasq on worker-01."
        return 1
    }

    if [[ -z "$TAILSCALE_API_TOKEN" ]]; then
        echo "dns-sync: TAILSCALE_API_TOKEN is not set, skipping Tailscale admin update."
        echo "Generate a token at https://login.tailscale.com/admin/settings/keys,"
        echo "export TAILSCALE_API_TOKEN=<token> (or add it to .env), then rerun '$0 dns-sync'."
        echo "Until then, set the restricted nameserver for ${TAILNET_DNS_ZONE} to ${ts_ip} in the admin console."
        return 1
    fi

    # Merge with existing split-DNS entries so other zones are preserved.
    current=$(curl -sS -u "${TAILSCALE_API_TOKEN}:" "https://api.tailscale.com/api/v2/tailnet/${TAILSCALE_TAILNET}/dns/split-dns" || echo "{}")
    merged=$(echo "$current" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if not isinstance(data, dict):
    data = {}
data['${TAILNET_DNS_ZONE}'] = ['${ts_ip}']
print(json.dumps(data))
")
    curl -sS -u "${TAILSCALE_API_TOKEN}:" -X PUT \
        -H "Content-Type: application/json" \
        --data "$merged" \
        "https://api.tailscale.com/api/v2/tailnet/${TAILSCALE_TAILNET}/dns/split-dns" || {
        echo "dns-sync: Tailscale API update failed."
        return 1
    }

    echo ""
    echo "dns-sync: tailnet split-DNS updated: ${TAILNET_DNS_ZONE} -> ${ts_ip}"

    if dig +short @"$ts_ip" "production.${TAILNET_DNS_ZONE}" | grep -qE '^100\.'; then
        echo "dns-sync: verified production.${TAILNET_DNS_ZONE} resolves via ${ts_ip}."
    else
        echo "dns-sync: WARNING: verification query failed."
        return 1
    fi
}

# Wait for all VMs. Usage: wait_all_vms [timeout_seconds]
wait_all_vms() {
    local timeout="${1:-$WAIT_TIMEOUT_DEFAULT}"
    local deadline failed=0
    deadline=$(( $(date +%s) + timeout ))

    echo "Waiting for cloud-init + tailscale on all VMs (timeout ${timeout}s)..."
    local ip
    ip=$(vm_ip "$VM_CP_MAC" "$VM_CP_IP")
    wait_one_vm "$VM_CP" "$ip" "$deadline" || failed=1
    ip=$(vm_ip "$VM_WORKER_MAC" "$VM_WORKER_IP")
    wait_one_vm "$VM_WORKER" "$ip" "$deadline" || failed=1
    ip=$(vm_ip "$VM_WORKER2_MAC" "$VM_WORKER2_IP")
    wait_one_vm "$VM_WORKER2" "$ip" "$deadline" || failed=1

    if (( failed != 0 )); then
        echo "DONE with errors: one or more VMs are not ready. Check with: $0 ips"
        return 1
    fi
    echo "All VMs are ready (cloud-init done + tailscale up)."
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
        export TF_VAR_tailscale_auth_key="$tailscale_auth_key"
        export TF_VAR_tailscale_suffix="$tailscale_suffix"
        terraform apply -auto-approve || exit 1
        # After (re)builds the worker may have a new tailnet IP: wait for
        # readiness, then repoint the split-DNS zone so the tailnet name
        # keeps working from every device with no manual edits.
        wait_all_vms "${2:-$WAIT_TIMEOUT_DEFAULT}" || exit 1
        dns_sync
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
    "wait")
        wait_all_vms "${2:-$WAIT_TIMEOUT_DEFAULT}"
        ;;
    "dns-sync")
        dns_sync
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
        echo "  init              - Download base images and initialize Terraform"
        echo "  apply             - Create VMs with terraform apply (runs twice for IPs)"
        echo "  destroy           - Destroy all VMs"
        echo "  start             - Start all VMs"
        echo "  stop              - Graceful shutdown all VMs"
        echo "  force-stop        - Force stop (destroy) all VMs"
        echo "  ips               - Show DHCP leases and VM status"
        echo "  wait [timeout]    - Wait for cloud-init done + tailscale up on all VMs (default 600s)"
        echo "  dns-sync          - Repoint k8s.astrolumina.ro split-DNS at worker-01's live tailnet IP"
        echo "  status            - Show running VMs"
        echo "  recreate-network  - Recreate network (for new MACs)"
        echo ""

        echo "Examples:"
        echo "  $0 init              # First time setup"
        echo "  $0 apply             # Create VMs"
        echo "  $0 wait              # Wait for cloud-init + tailscale (or: $0 apply && $0 wait)"
        echo "  $0 ips               # Get VM IPs"
        echo "  $0 recreate-network  # Recreate network with new DHCP reservations"
        exit 1
        ;;
esac