#!/usr/bin/env bash
# Artificial Linux - Phase 10: Create full bootable LIVE ISO
# Includes root filesystem (squashfs), kernel, initramfs, and TinyLlama GGUF model.
# Run on host or in VM. Uses xorriso, grub-mkrescue, mksquashfs, busybox-static.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${ALFS_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
BRANDING_DIR="$PROJECT_ROOT/branding"
BUILD_DIR="${ALFS_BUILD_DIR:-$PROJECT_ROOT/build}"
ISO_DIR="$BUILD_DIR/iso"
LOG_DIR="${ALFS_LOG_DIR:-/var/log/alfs}"
mkdir -p "$LOG_DIR" "$ISO_DIR"
LOG="$LOG_DIR/10-create-iso.log"
exec 1> >(tee -a "$LOG") 2>&1

echo "=== Artificial Linux - Create LIVE ISO ($(date)) ==="

# Helper: run command with sudo only if not root
as_root() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Live ISO must pack a root that has /sbin/init (systemd). On the build VM the
# working system is / (Debian); $LFS (/mnt/lfs) is the LFS build tree and has no init.
# So we pack / unless ALFS_LIVE_ROOT is set or LFS exists and has /sbin/init.
ROOT_DIR="/"
if [[ -n "${ALFS_LIVE_ROOT:-}" ]] && [[ -d "$ALFS_LIVE_ROOT" ]] && [[ -x "$ALFS_LIVE_ROOT/sbin/init" ]]; then
    ROOT_DIR="$ALFS_LIVE_ROOT"
elif [[ -n "${LFS:-}" ]] && [[ "$LFS" != "/" ]] && [[ -d "$LFS" ]] && [[ -x "$LFS/sbin/init" ]]; then
    ROOT_DIR="$LFS"
fi
echo "Packaging root: $ROOT_DIR (must contain /sbin/init)"

# Install xorriso, grub (BIOS + EFI), squashfs-tools, busybox-static, mtools (mformat for grub-mkrescue)
# grub-pc-bin = i386-pc (BIOS); grub-efi-amd64-bin = x86_64-efi (UEFI). mtools provides mformat.
if ! command -v xorriso &>/dev/null || ! command -v mksquashfs &>/dev/null || ! command -v busybox &>/dev/null || ! command -v mformat &>/dev/null || ! command -v rsync &>/dev/null; then
    for try in apt-get dnf yum; do
        if command -v "$try" &>/dev/null; then
            echo "Installing xorriso, grub (pc+efi-amd64), squashfs-tools, busybox-static, mtools, rsync..."
            ("$try" install -y xorriso grub-pc-bin grub-efi-amd64-bin squashfs-tools busybox-static mtools rsync 2>/dev/null) || true
            break
        fi
    done
fi
if ! command -v xorriso &>/dev/null; then
    echo "Install: apt install xorriso grub-pc-bin grub-efi-amd64-bin squashfs-tools busybox-static mtools rsync"
    exit 1
fi
command -v rsync &>/dev/null || { echo "rsync not found. Install rsync (needed for staging root)."; exit 1; }
command -v mksquashfs &>/dev/null || { echo "mksquashfs not found. Install squashfs-tools"; exit 1; }
command -v busybox &>/dev/null || [[ -x /usr/bin/busybox ]] || { echo "busybox not found. Install busybox-static"; exit 1; }
command -v mformat &>/dev/null || { echo "mformat not found. Install mtools (required by grub-mkrescue)."; exit 1; }

# Ensure GGUF model is in the root we're packaging
MODEL_DEST="$ROOT_DIR/usr/share/models/artificial-linux-slm.gguf"
if [[ ! -f "$MODEL_DEST" ]]; then
    GGUF_SRC="${ALFS_GGUF:-}"
    [[ -z "$GGUF_SRC" ]] && for f in /tmp/tinyllama-1.1b-chat-v1.0-Q5_K_M.gguf /tmp/*-Q5_K_M.gguf; do
        [[ -f "$f" ]] && GGUF_SRC="$f" && break
    done
    if [[ -n "$GGUF_SRC" ]] && [[ -f "$GGUF_SRC" ]]; then
        echo "Copying GGUF model into root: $GGUF_SRC -> $MODEL_DEST"
        as_root mkdir -p "$(dirname "$MODEL_DEST")"
        as_root cp -v "$GGUF_SRC" "$MODEL_DEST"
    else
        if [[ "${ALFS_ALLOW_NO_MODEL:-0}" == "1" ]]; then
            echo "WARNING: No GGUF at $MODEL_DEST or ALFS_GGUF/tmp. Live system will lack SLM until you copy artificial-linux-slm.gguf to /usr/share/models/"
        else
            echo "ERROR: No GGUF found for the live ISO."
            echo "Expected: $MODEL_DEST"
            echo "Provide one of:"
            echo "  - ALFS_GGUF=/path/to/model.gguf"
            echo "  - copy a *-Q5_K_M.gguf into /tmp/ before running phase 10"
            echo "If you really want to build an ISO without a model, set: ALFS_ALLOW_NO_MODEL=1"
            exit 1
        fi
    fi
fi

# Apply branding to root
if [[ -d "$BRANDING_DIR" ]]; then
    [[ -f "$BRANDING_DIR/os-release" ]] && as_root cp -v "$BRANDING_DIR/os-release" "$ROOT_DIR/etc/os-release" 2>/dev/null || true
    [[ -f "$BRANDING_DIR/lsb-release" ]] && as_root cp -v "$BRANDING_DIR/lsb-release" "$ROOT_DIR/etc/lsb-release" 2>/dev/null || true
    [[ -f "$BRANDING_DIR/issue" ]] && as_root cp -v "$BRANDING_DIR/issue" "$ROOT_DIR/etc/issue" 2>/dev/null || true
fi

# --- Live ISO layout ---
ISO_NAME="artificial-linux-1.0-live.iso"
WORK="$BUILD_DIR/iso-work"
LIVE="$WORK/live"
INITRAMFS_DIR="$BUILD_DIR/initramfs"
rm -rf "$WORK" "$INITRAMFS_DIR"
mkdir -p "$WORK/boot/grub" "$LIVE" "$INITRAMFS_DIR"

# 1) Kernel (phase 05 installs to $LFS/boot; we may be packaging / so check both)
LFS_ROOT="${LFS:-/mnt/lfs}"
KERNEL=""
for base in "$ROOT_DIR" "$LFS_ROOT"; do
    [[ -f "$base/boot/vmlinuz-artificial-linux" ]] && KERNEL="$base/boot/vmlinuz-artificial-linux" && break
    [[ -f "$base/boot/vmlinuz" ]] && KERNEL="$base/boot/vmlinuz" && break
done
if [[ -z "$KERNEL" ]] || [[ ! -f "$KERNEL" ]]; then
    echo "Kernel not found. Checked: $ROOT_DIR/boot, $LFS_ROOT/boot (vmlinuz-artificial-linux or vmlinuz)"
    exit 1
fi
cp -v "$KERNEL" "$WORK/boot/vmlinuz-artificial-linux"

# 2) Root filesystem as squashfs (exclude runtime and large paths; ISO Level 3 used so >4GB is OK)
# Use a staging dir so we never pack /proc, /sys, /dev (would be huge/slow); create empty mountpoints.
STAGING="$WORK/root-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
RSYNC_EXCLUDE=(
    'dev' 'proc' 'sys' 'run' 'tmp' 'home' 'root/.cache' 'lost+found'
    '.cache' 'var/cache' 'var/tmp' 'var/run' 'var/log'
    'boot/*.img' 'boot/vmlinuz*'
    'usr/share/doc' 'usr/share/man' 'usr/share/info' 'usr/share/locale'
    'usr/lib/debug' 'usr/lib/valgrind' 'usr/share/gnome/help' 'usr/share/help'
    'usr/share/icons' 'usr/share/fonts'
    '*.pyc' '*.pyo'
)
[[ -n "${ALFS_SQUASHFS_EXCLUDE:-}" ]] && RSYNC_EXCLUDE+=($ALFS_SQUASHFS_EXCLUDE)
echo "Syncing root into staging (excluding volatile and large paths)..."
rsync -a --delete-excluded \
    $(printf " --exclude=%s" "${RSYNC_EXCLUDE[@]}") \
    "$ROOT_DIR/" "$STAGING/" 2>/dev/null || true
# Ensure mountpoints exist for initramfs (proc, sys, dev, run, tmp)
mkdir -p "$STAGING"/{dev,proc,sys,run,tmp}
chmod 1777 "$STAGING/tmp"
echo "Creating live root filesystem (squashfs)..."
mksquashfs "$STAGING" "$LIVE/filesystem.squashfs" \
    -noappend -no-xattrs -comp xz 2>/dev/null || \
mksquashfs "$STAGING" "$LIVE/filesystem.squashfs" \
    -noappend -no-xattrs -comp gzip 2>/dev/null || true
rm -rf "$STAGING"
if [[ ! -f "$LIVE/filesystem.squashfs" ]]; then
    echo "mksquashfs failed. Check disk space."
    exit 1
fi
# ISO 9660 Level 3 is used so files (e.g. squashfs with TinyLlama) can exceed 4GB
echo "Squashfs size: $(du -h "$LIVE/filesystem.squashfs" | cut -f1)"

# 3) Initramfs: mount ISO, mount squashfs, switch_root to it
BUSYBOX=""
for b in /usr/bin/busybox /bin/busybox; do [[ -x "$b" ]] && BUSYBOX="$b" && break; done
if [[ -z "$BUSYBOX" ]]; then
    echo "busybox not found. Install busybox-static."
    exit 1
fi
mkdir -p "$INITRAMFS_DIR"/{bin,proc,sys,dev,run,mnt/iso,mnt/rootfs}
cp -v "$BUSYBOX" "$INITRAMFS_DIR/bin/busybox"
chmod +x "$INITRAMFS_DIR/bin/busybox"
ln -sf busybox "$INITRAMFS_DIR/bin/sh"
ln -sf busybox "$INITRAMFS_DIR/bin/mount"
ln -sf busybox "$INITRAMFS_DIR/bin/switch_root"
ln -sf busybox "$INITRAMFS_DIR/bin/umount"
ln -sf busybox "$INITRAMFS_DIR/bin/mkdir"
ln -sf busybox "$INITRAMFS_DIR/bin/mknod"
ln -sf busybox "$INITRAMFS_DIR/bin/sleep"
ln -sf busybox "$INITRAMFS_DIR/bin/echo"

cat > "$INITRAMFS_DIR/init" << 'INITEOF'
#!/bin/sh
export PATH=/bin
# Redirect to console as soon as possible (kernel may have created /dev/console)
[ -c /dev/console ] && exec 0</dev/console 1>/dev/console 2>&1
mount -t proc proc /proc
mount -t sysfs sysfs /sys
# devtmpfs may fail if kernel has none; create minimal /dev/console for output
if ! mount -t devtmpfs devtmpfs /dev 2>/dev/null; then
    [ ! -c /dev/console ] && mknod -m 622 /dev/console c 5 1
    [ ! -c /dev/null ] && mknod -m 666 /dev/null c 1 3
fi
[ -c /dev/console ] && exec 0</dev/console 1>/dev/console 2>&1
mkdir -p /run /mnt/iso /mnt/rootfs

echo "Artificial Linux init: waiting for block devices..."
n=0
while [ ! -e /dev/sr0 ] && [ ! -e /dev/sda ] && [ ! -e /dev/cdrom ] && [ ! -d /dev/disk/by-label ]; do
    sleep 0.5
    n=$((n+1))
    [ $n -gt 40 ] && break
done
sleep 1

echo "Artificial Linux init: mounting ISO..."
MNT_OK=0
# Try CD (sr0, cdrom, by-label) first; then disk (sda) in case QEMU was run with ISO as first arg instead of -cdrom
for dev in /dev/disk/by-label/ARTIFICIAL_LINUX /dev/sr0 /dev/cdrom /dev/sda /dev/sda1; do
    [ ! -e "$dev" ] && continue
    if mount -t iso9660 -o ro "$dev" /mnt/iso 2>/dev/null; then
        [ -f /mnt/iso/live/filesystem.squashfs ] && MNT_OK=1 && break
        umount /mnt/iso 2>/dev/null || true
    fi
done
if [ "$MNT_OK" -ne 1 ] || [ ! -f /mnt/iso/live/filesystem.squashfs ]; then
    echo "ERROR: Live squashfs not found at /mnt/iso/live/filesystem.squashfs"
    echo "Tip: Boot QEMU with -cdrom artificial-linux-1.0-live.iso -boot d (or BOOT_LIVE_ISO=1 ./scripts/00-setup-vm.sh)"
    echo "CD contents: $(ls -la /mnt/iso 2>/dev/null || true)"
    exec /bin/sh
fi

echo "Artificial Linux init: mounting rootfs..."
if ! mount -t squashfs -o ro /mnt/iso/live/filesystem.squashfs /mnt/rootfs; then
    echo "ERROR: Failed to mount squashfs. Kernel needs CONFIG_SQUASHFS=y and CONFIG_BLK_DEV_LOOP=y (built-in)."
    echo "Rebuild kernel (phase 05) with config/kernel.config then rebuild ISO."
    exec /bin/sh
fi
# systemd needs writable /run and /tmp; root is read-only squashfs
mkdir -p /mnt/rootfs/run /mnt/rootfs/tmp
mount -t tmpfs tmpfs /mnt/rootfs/run
mount -t tmpfs tmpfs /mnt/rootfs/tmp
# Move kernel mounts into new root so init sees /proc, /sys, /dev (BusyBox: -o move)
mount -o move /proc /mnt/rootfs/proc
mount -o move /sys /mnt/rootfs/sys
mount -o move /dev /mnt/rootfs/dev
echo "Artificial Linux init: switching to root, starting /sbin/init..."
exec /bin/busybox switch_root /mnt/rootfs /sbin/init
INITEOF
chmod +x "$INITRAMFS_DIR/init"

echo "Creating initramfs..."
( cd "$INITRAMFS_DIR" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "$WORK/boot/initrd.img" )
rm -rf "$INITRAMFS_DIR"

# 4) GRUB config for live boot (force visible console; ignore_loglevel shows all kernel msgs)
cat > "$WORK/boot/grub/grub.cfg" << 'GRUB'
set default=0
set timeout=5
menuentry "Artificial Linux (Live)" {
    linux /boot/vmlinuz-artificial-linux boot=live console=tty0 console=ttyS0,115200n8 ignore_loglevel loglevel=8 panic=30
    initrd /boot/initrd.img
    boot
}
menuentry "Artificial Linux (Live, quiet)" {
    linux /boot/vmlinuz-artificial-linux boot=live console=tty0 quiet
    initrd /boot/initrd.img
    boot
}
menuentry "Artificial Linux (Debug shell)" {
    linux /boot/vmlinuz-artificial-linux boot=live console=tty0 ignore_loglevel init=/bin/sh
    initrd /boot/initrd.img
    boot
}
GRUB

# 5) Build ISO (ISO 9660 Level 3 allows files >4GB, e.g. squashfs with TinyLlama)
echo "Building ISO image..."
if command -v grub-mkrescue &>/dev/null; then
    # Options before $WORK are passed as mkisofs options; after -- would be native xorriso only
    grub-mkrescue -o "$ISO_DIR/$ISO_NAME" -volid "ARTIFICIAL_LINUX" -iso-level 3 "$WORK"
else
    xorriso -as mkisofs -o "$ISO_DIR/$ISO_NAME" \
        -volid "ARTIFICIAL_LINUX" -r -J -V "ARTIFICIAL_LINUX" -iso-level 3 "$WORK"
fi

if [[ -f "$ISO_DIR/$ISO_NAME" ]]; then
    echo "LIVE ISO created: $ISO_DIR/$ISO_NAME ($(du -h "$ISO_DIR/$ISO_NAME" | cut -f1))"
else
    echo "ISO creation failed."
    exit 1
fi
echo "Done. Share: $ISO_DIR/$ISO_NAME"
exit 0
