#!/usr/bin/env bash
# Artificial Linux - Phase 0: Create and boot QEMU VM for LFS build
# Run from project root on macOS. Requires QEMU installed (brew install qemu).

set -euo pipefail

# Safety check: Don't run VM setup inside a VM
if [[ -f /proc/cpuinfo ]] && grep -qi "QEMU\|KVM\|VirtualBox\|VMware" /proc/cpuinfo 2>/dev/null; then
    echo "=== Skipping Phase 0: Already inside a VM ==="
    echo "This script is only for setting up QEMU from the host (macOS)."
    echo "You're already inside the VM. Skip to phase 01:"
    echo "  ALFS_FROM=01 ./scripts/build-all.sh"
    exit 0
elif [[ -d /sys/class/dmi/id ]] && grep -qi "QEMU\|VirtualBox\|VMware" /sys/class/dmi/id/* 2>/dev/null; then
    echo "=== Skipping Phase 0: Already inside a VM ==="
    echo "This script is only for setting up QEMU from the host (macOS)."
    echo "You're already inside the VM. Skip to phase 01:"
    echo "  ALFS_FROM=01 ./scripts/build-all.sh"
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$PROJECT_ROOT/config"
BUILD_DIR="${ALFS_BUILD_DIR:-$PROJECT_ROOT/build}"
VM_DIR="$BUILD_DIR/vm"
ISO_DIR="$BUILD_DIR/iso"

# Load QEMU config
if [[ -f "$CONFIG_DIR/qemu.conf" ]]; then
    # shellcheck source=../config/qemu.conf
    source "$CONFIG_DIR/qemu.conf" 2>/dev/null || true
fi

VM_MEMORY="${VM_MEMORY:-8G}"
VM_CPUS="${VM_CPUS:-6}"
VM_DISK_SIZE="${VM_DISK_SIZE:-80G}"
VM_DISK_FILE="${VM_DISK_FILE:-lfs-build.qcow2}"
SSH_HOST_PORT="${SSH_HOST_PORT:-2222}"
QEMU_ACCEL="${QEMU_ACCEL:-hvf}"
DEBIAN_ISO_URL="${DEBIAN_ISO_URL:-https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.5.0-amd64-netinst.iso}"
DEBIAN_ISO_FILE="${DEBIAN_ISO_FILE:-debian-12-netinst.iso}"

mkdir -p "$VM_DIR" "$ISO_DIR"

DISK_PATH="$VM_DIR/$VM_DISK_FILE"
LIVE_ISO_NAME="${LIVE_ISO_NAME:-artificial-linux-1.0-live.iso}"
LIVE_ISO_PATH="$ISO_DIR/$LIVE_ISO_NAME"
# Default: Debian installer ISO (for initial setup). Override with BOOT_LIVE_ISO=1 to boot the built live ISO.
if [[ "${BOOT_LIVE_ISO:-0}" == "1" ]]; then
    ISO_PATH="$LIVE_ISO_PATH"
else
    ISO_PATH="$ISO_DIR/$DEBIAN_ISO_FILE"
fi

echo "=== Artificial Linux - VM Setup ==="
echo "Project root: $PROJECT_ROOT"
echo "Build dir:    $BUILD_DIR"
echo "VM disk:     $DISK_PATH"
echo "ISO:         $ISO_PATH"
echo ""

# Download Debian netinst ISO if not present
if [[ ! -f "$ISO_PATH" ]]; then
    echo "Downloading Debian netinst ISO (this may take several minutes)..."
    curl -L -o "$ISO_PATH" "$DEBIAN_ISO_URL" --progress-bar || {
        echo "Download failed. You can manually place $DEBIAN_ISO_FILE in $ISO_DIR"
        echo "Or set DEBIAN_ISO_URL in config/qemu.conf"
        exit 1
    }
    # Verify it's not a redirect/error page (ISO should be >400MB)
    SIZE=$(stat -f%z "$ISO_PATH" 2>/dev/null || stat -c%s "$ISO_PATH" 2>/dev/null || echo 0)
    if [[ $SIZE -lt 400000000 ]]; then
        echo "Downloaded file is too small ($SIZE bytes). Expected ~600MB."
        echo "The URL may have changed. Please download manually:"
        echo "  https://www.debian.org/distrib/netinst"
        echo "  Place file as: $ISO_PATH"
        rm -f "$ISO_PATH"
        exit 1
    fi
    echo "ISO downloaded successfully ($SIZE bytes)."
else
    echo "ISO already present: $ISO_PATH"
fi

# Create QCOW2 disk if not present
if [[ ! -f "$DISK_PATH" ]]; then
    echo "Creating QCOW2 disk ($VM_DISK_SIZE)..."
    qemu-img create -f qcow2 "$DISK_PATH" "$VM_DISK_SIZE"
fi

# Build QEMU command
# -accel hvf on macOS for near-native speed
# -nic user,hostfwd=tcp::2222-:22 for SSH from host
QEMU_OPTS=(
    -m "$VM_MEMORY"
    -smp "$VM_CPUS"
    -cpu host
    -accel "$QEMU_ACCEL"
    -drive "file=$DISK_PATH,format=qcow2,if=virtio"
    -netdev "user,id=net0,hostfwd=tcp::${SSH_HOST_PORT}-:22"
    -device "virtio-net-pci,netdev=net0"
)

# Boot from CD: BOOT_FROM_ISO=1 (Debian install) or BOOT_LIVE_ISO=1 (Artificial Linux live)
if [[ "${BOOT_LIVE_ISO:-0}" == "1" ]]; then
    if [[ ! -f "$LIVE_ISO_PATH" ]]; then
        echo "Live ISO not found: $LIVE_ISO_PATH"
        echo "Build it first (in VM): ./scripts/10-create-iso.sh"
        exit 1
    fi
    echo "Booting from Live ISO: $LIVE_ISO_PATH"
    QEMU_OPTS+=(-cdrom "$LIVE_ISO_PATH" -boot d)
elif [[ "${BOOT_FROM_ISO:-0}" == "1" ]]; then
    echo "Booting from ISO (install Debian, enable SSH, then power off)."
    echo "After install: ssh -p $SSH_HOST_PORT user@localhost"
    QEMU_OPTS+=(-cdrom "$ISO_PATH" -boot d)
fi

# Display mode: GUI window (default) or headless terminal (set QEMU_NOGRAPHIC=1)
if [[ "${QEMU_NOGRAPHIC:-0}" == "1" ]]; then
    echo "Running in headless mode (serial console)."
    echo "Tip: Use Ctrl+A then X to quit QEMU."
    QEMU_OPTS+=(-nographic)
else
    echo "Opening QEMU GUI window..."
    echo "Tip: The VM will open in a separate window."
fi

echo "To connect via SSH after Linux is installed: ssh -p $SSH_HOST_PORT <user>@localhost"
echo "To transfer files: scp -P $SSH_HOST_PORT <file> <user>@localhost:<path>"
echo ""

exec qemu-system-x86_64 "${QEMU_OPTS[@]}"
