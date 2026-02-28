#!/usr/bin/env bash
# Artificial Linux - Phase 6: Configure boot (GRUB, fstab, hostname, systemd)
# Run inside chroot or on finished LFS system.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$PROJECT_ROOT/config"
LOG_DIR="${ALFS_LOG_DIR:-/var/log/alfs}"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/06-configure-boot.log"
exec 1> >(tee -a "$LOG") 2>&1

echo "=== Artificial Linux - Configure Boot ($(date)) ==="

[[ -f "$CONFIG_DIR/alfs.conf" ]] && source "$CONFIG_DIR/alfs.conf"
export LFS="${LFS:-/mnt/lfs}"
HOSTNAME="${HOSTNAME:-artificial-linux}"

# If we are inside chroot, LFS might be /
if [[ "$(stat -c %d:%i / 2>/dev/null)" == "$(stat -c %d:%i $LFS 2>/dev/null)" ]] || [[ "$LFS" == "/" ]]; then
    ROOT="/"
else
    ROOT="$LFS"
fi

# Ensure etc and boot exist
mkdir -p "$ROOT/etc" "$ROOT/boot/grub"

# /etc/hostname
echo "$HOSTNAME" > "$ROOT/etc/hostname"
# /etc/hosts
cat > "$ROOT/etc/hosts" << EOF
127.0.0.1 localhost
127.0.1.1 $HOSTNAME
EOF

# /etc/fstab (adjust for actual root device)
ROOT_DEV="${ROOT_DEV:-/dev/vda1}"
cat > "$ROOT/etc/fstab" << EOF
# device    mountpoint  fs-type  options       dump  fsck
$ROOT_DEV   /           ext4     defaults      1    1
proc        /proc       proc     nosuid,noexec  0    0
sysfs       /sys        sysfs    nosuid,noexec  0    0
devpts      /dev/pts    devpts   gid=5,mode=620 0    0
tmpfs       /run        tmpfs    defaults      0    0
EOF

# GRUB (if installed)
if command -v grub-install &>/dev/null; then
    mkdir -p "$ROOT/boot/grub"
    grub-install --target=i386-pc "$ROOT_DEV" --boot-directory="$ROOT/boot" 2>/dev/null || \
        grub-install --target=x86_64-efi --efi-directory="$ROOT/boot" --boot-directory="$ROOT/boot" 2>/dev/null || true
    cat > "$ROOT/boot/grub/grub.cfg" << 'GRUB'
set default=0
set timeout=3
menuentry "Artificial Linux" {
    linux /vmlinuz-artificial-linux root=/dev/vda1 ro
}
GRUB
fi

# systemd: enable basic target
[[ -d "$ROOT/etc/systemd/system" ]] && ln -sf /lib/systemd/system/multi-user.target "$ROOT/etc/systemd/system/default.target" 2>/dev/null || true

echo "Boot configuration complete. Next: 07-build-blfs.sh"
exit 0
