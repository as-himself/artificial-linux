#!/usr/bin/env bash
# Artificial Linux - Phase 2: Create LFS partition and lfs user (LFS Ch 2/4)
# Run as root or with sudo inside the Linux build VM.

set -euo pipefail

# Ensure sbin in PATH (groupadd, useradd, etc. live in /usr/sbin on Debian)
export PATH="/usr/sbin:/sbin:/usr/bin:/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$PROJECT_ROOT/config"
LOG_DIR="${ALFS_LOG_DIR:-/var/log/alfs}"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/02-create-lfs-user.log"
exec 1> >(tee -a "$LOG") 2>&1

echo "=== Artificial Linux - Create LFS User ($(date)) ==="

[[ -f "$CONFIG_DIR/alfs.conf" ]] && source "$CONFIG_DIR/alfs.conf"
LFS="${LFS:-/mnt/lfs}"

# Safety: never operate outside a dedicated LFS path (avoid chown damaging system)
case "$LFS" in
    /mnt/lfs|/mnt/lfs/*) ;;
    *)
        echo "LFS must be /mnt/lfs (or a subpath). Refusing to use LFS=$LFS"
        exit 1
        ;;
esac

# Helper: run command with sudo only if not root
as_root() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Create mount point
as_root mkdir -p "$LFS"
as_root chown "$(whoami):" "$LFS" 2>/dev/null || as_root chown root:root "$LFS"

# If we have a separate block device (e.g. /dev/vdb), format and mount it
# Otherwise use a directory (e.g. for single-disk VM)
LFS_DEV="${LFS_DEV:-}"
if [[ -n "$LFS_DEV" ]] && [[ -b "$LFS_DEV" ]]; then
    echo "Using block device $LFS_DEV for LFS"
    as_root mkfs -t ext4 "$LFS_DEV" 2>/dev/null || true
    as_root mount "$LFS_DEV" "$LFS"
    echo "$LFS_DEV $LFS ext4 defaults 0 1" | as_root tee -a /etc/fstab
else
    echo "No LFS_DEV set; using $LFS as directory (e.g. subdir on root fs)"
fi

# Create lfs user (LFS Ch 4)
if ! getent group lfs &>/dev/null; then
    as_root groupadd lfs
fi
if ! getent passwd lfs &>/dev/null; then
    as_root useradd -s /bin/bash -g lfs -m -k /dev/null lfs
    echo "Set password for lfs user (or leave blank for no login):"
    as_root passwd lfs || true
fi
as_root chown -R lfs:lfs "$LFS"

# lfs user environment
LFS_PROFILE="/home/lfs/.bash_profile"
LFS_BASHRC="/home/lfs/.bashrc"
as_root tee "$LFS_PROFILE" << 'LFSENV'
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' /bin/bash
LFSENV
as_root tee "$LFS_BASHRC" << LFSRC
set +h
umask 022
LFS=${LFS:-/mnt/lfs}
LC_ALL=POSIX
LFS_TGT=\$(uname -m)-lfs-linux-gnu
PATH=/usr/bin
[[ -d /tools/bin ]] && PATH=/tools/bin:\$PATH
export LFS LC_ALL LFS_TGT PATH
LFSRC
as_root chown lfs:lfs "$LFS_PROFILE" "$LFS_BASHRC"

# Create LFS directory layout (Ch 5)
if [[ $EUID -eq 0 ]]; then
    su -c "mkdir -p $LFS/sources $LFS/tools" lfs
    su -c "ln -sf $LFS/tools /home/lfs/tools 2>/dev/null || true" lfs
else
    sudo -u lfs bash -c "mkdir -p $LFS/sources $LFS/tools"
    sudo -u lfs ln -sf "$LFS/tools" /home/lfs/tools 2>/dev/null || true
fi
as_root chown -R lfs:lfs "$LFS"

echo "LFS=$LFS" | as_root tee -a /etc/environment 2>/dev/null || true
echo "LFS directory: $LFS (owned by lfs:lfs). Switch to user lfs and run 03-build-toolchain.sh."
exit 0
