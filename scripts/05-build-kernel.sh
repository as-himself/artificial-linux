#!/usr/bin/env bash
# Artificial Linux - Phase 5: Build Linux kernel with BPF/BTF/LSM (LFS Ch 10)
# Run inside chroot or on finished LFS system. Uses config/kernel.config fragment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$PROJECT_ROOT/config"
LOG_DIR="${ALFS_LOG_DIR:-/var/log/alfs}"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/05-build-kernel.log"
exec 1> >(tee -a "$LOG") 2>&1

echo "=== Artificial Linux - Build Kernel ($(date)) ==="

[[ -f "$CONFIG_DIR/alfs.conf" ]] && source "$CONFIG_DIR/alfs.conf"
export LFS="${LFS:-/mnt/lfs}"
KERNEL_SRC="${KERNEL_SRC:-$LFS/sources/linux-${LINUX_VER}}"
KERNEL_BUILD="${KERNEL_BUILD:-$KERNEL_SRC/build}"
FRAGMENT="$CONFIG_DIR/kernel.config"

# If not in chroot, use system paths
if [[ ! -d "$LFS/sources" ]]; then
    KERNEL_SRC="${KERNEL_SRC:-/usr/src/linux}"
    KERNEL_BUILD="$KERNEL_SRC"
fi

mkdir -p "$KERNEL_SRC" "$KERNEL_BUILD" "$LFS/boot"
cd "$KERNEL_SRC"

# Ensure kernel source is present
if [[ ! -f "Makefile" ]]; then
    echo "Kernel source not found at $KERNEL_SRC. Extract linux-${LINUX_VER}.tar.xz here."
    if [[ -f "$LFS/sources/linux-${LINUX_VER}.tar.xz" ]]; then
        tar xf "$LFS/sources/linux-${LINUX_VER}.tar.xz" -C "$(dirname "$KERNEL_SRC")"
        KERNEL_SRC="$(dirname "$KERNEL_SRC")/linux-${LINUX_VER}"
        cd "$KERNEL_SRC"
    else
        exit 1
    fi
fi

# Phase 03 deletes non-.h files in usr/include (including Makefile), which breaks mrproper.
# Restore a minimal usr/include/Makefile so "make mrproper" can run.
if [[ ! -f usr/include/Makefile ]]; then
    mkdir -p usr/include
    printf '%s\n' 'clean:' '	@:' > usr/include/Makefile
fi
make mrproper
make defconfig
if [[ -f "$FRAGMENT" ]]; then
    echo "Applying BPF/BTF/LSM config fragment..."
    while read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^# ]] && continue
        key="${line%%=*}"
        val="${line#*=}"
        sed -i "s/^# *$key is not set\$/$key=$val/" .config 2>/dev/null || true
        grep -q "^$key=" .config && sed -i "s|^$key=.*|$key=$val|" .config || echo "$key=$val" >> .config
    done < "$FRAGMENT"
    make olddefconfig
fi

make ${MAKEFLAGS:-} || {
    echo ""
    echo "=== Last 60 lines of log (first error may be above) ==="
    tail -60 "$LOG" 2>/dev/null || true
    exit 1
}
make modules_install
cp -v arch/$(uname -m)/boot/bzImage "$LFS/boot/vmlinuz-artificial-linux" 2>/dev/null || \
    cp -v arch/x86_64/boot/bzImage "$LFS/boot/vmlinuz-artificial-linux" 2>/dev/null || \
    cp -v arch/$(uname -m)/boot/Image "$LFS/boot/vmlinuz-artificial-linux" 2>/dev/null || true

echo "Kernel build complete. Next: 06-configure-boot.sh"
exit 0
