#!/bin/bash
case $1 in
    "init")
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
        qcowq2_image="${libvirt_img_path}/ubuntu.qcow2"
        if [[ ! -f "$qcowq2_image" ]]; then
            echo "Ubuntu QCOW2 image not found at $qcowq2_image"
            sudo qemu-img convert -O qcow2 "$base_image" "$qcowq2_image"
            sudo chmod 644 "$qcowq2_image"
            sudo chown libvirt-qemu:kvm "$qcowq2_image"
        fi
        ;;
    "apply")
        
        ;;
    "destroy")
        echo "def"
        ;;
    *)
        echo "Not an option"
        return 0
        ;;
esac