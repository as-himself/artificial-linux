#!/usr/bin/env bash
# Artificial Linux - Phase 4: Build LFS base system in chroot (LFS Ch 7-8)
# Run from HOST: mounts virtfs, then chroots into $LFS and runs the inner build.
# Alternatively, run the inner script manually after chrooting.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$PROJECT_ROOT/config"
LOG_DIR="${ALFS_LOG_DIR:-/var/log/alfs}"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/04-build-chroot.log"
exec 1> >(tee -a "$LOG") 2>&1

echo "=== Artificial Linux - Build Chroot ($(date)) ==="

[[ -f "$CONFIG_DIR/alfs.conf" ]] && source "$CONFIG_DIR/alfs.conf"
export LFS="${LFS:-/mnt/lfs}"

# Ensure LFS exists and has required layout
[[ ! -d "$LFS" ]] && { echo "LFS directory $LFS does not exist. Run 02-create-lfs-user.sh first."; exit 1; }

# Create mount points before mounting (LFS Ch 7.2)
mkdir -p "$LFS/dev" "$LFS/dev/pts" "$LFS/proc" "$LFS/sys" "$LFS/run"

# Mount virtual kernel filesystems (LFS Ch 7.2)
mount -v --bind /dev "$LFS/dev"
mount -v --bind /dev/pts "$LFS/dev/pts"
mount -vt proc proc "$LFS/proc"
mount -vt sysfs sysfs "$LFS/sys"
mount -vt tmpfs tmpfs "$LFS/run"
[[ -h "$LFS/dev/shm" ]] && mkdir -p "$LFS/$(readlink $LFS/dev/shm)" && mount -vt tmpfs tmpfs "$LFS/$(readlink $LFS/dev/shm)" || true

# Enter chroot and run build (inner script)
INNER_SCRIPT="$LFS/root/chroot-build.sh"
mkdir -p "$LFS/root"
cat > "$INNER_SCRIPT" << 'INNER'
#!/bin/bash
set -e
export LFS=/mnt/lfs
export PATH=/usr/bin:/usr/sbin:/bin:/sbin
[[ -d /tools/bin ]] && export PATH=/tools/bin:$PATH
cd /sources 2>/dev/null || cd $LFS/sources

# Ch 7-8: Install packages in order (create directories, then build)
# Glibc, Zlib, Bzip2, Xz, Zstd, File, Readline, M4, Bc, Flex, Tcl, Expect, DejaGNU,
# Pkgconf, Binutils, GMP, MPFR, MPC, Attr, Acl, Libcap, Libxcrypt, Shadow, GCC,
# Ncurses, Sed, Psmisc, Gettext, Bison, Grep, Bash, Libtool, GDBM, Gperf, Expat,
# Inetutils, Less, Perl, XML::Parser, Intltool, Autoconf, Automake, OpenSSL,
# Kmod, Libelf, Coreutils, Check, Diffutils, Gawk, Findutils, Groff, GRUB,
# Gzip, IPRoute2, Kbd, Libpipeline, Make, Patch, Tar, Texinfo, Util-linux,
# Man-DB, Procps-ng, E2fsprogs, Sysklogd, Systemd, D-Bus

# Placeholder: full implementation follows LFS book step-by-step
echo "Chroot build: run LFS Ch 7-8 commands here or use jhalfs-generated scripts."
touch $LFS/chroot-build-done 2>/dev/null || true
INNER
chmod +x "$INNER_SCRIPT"

# Chroot needs a shell: use /tools/bin/bash if built, else bind-mount host /bin
CHROOT_SHELL=""
if [[ -x "$LFS/tools/bin/bash" ]]; then
    CHROOT_SHELL="/tools/bin/bash"
elif [[ -x "$LFS/bin/bash" ]]; then
    CHROOT_SHELL="/bin/bash"
else
    echo "No shell in chroot. Bind-mounting host /bin and /lib for chroot..."
    mkdir -p "$LFS/bin" "$LFS/lib" "$LFS/lib64"
    mount -v --bind /bin "$LFS/bin"
    [[ -d /lib ]] && mount -v --bind /lib "$LFS/lib" 2>/dev/null || true
    [[ -d /lib64 ]] && mount -v --bind /lib64 "$LFS/lib64" 2>/dev/null || true
    CHROOT_SHELL="/bin/bash"
    BIND_BIN=1
fi

# chroot is in coreutils; use full path (PATH may be minimal when run from build-all)
CHROOT_CMD=""
for p in /usr/bin/chroot /usr/sbin/chroot; do
    [[ -x "$p" ]] && CHROOT_CMD="$p" && break
done
if [[ -z "$CHROOT_CMD" ]]; then
    echo "chroot not found. Install with: sudo apt install coreutils"
    exit 1
fi

# Don't use env - it may live in /usr/bin which doesn't exist in minimal chroot.
# Run the shell and set environment inside the -c script.
"$CHROOT_CMD" "$LFS" "$CHROOT_SHELL" -c "export HOME=/root TERM='$TERM' PATH=/usr/bin:/usr/sbin:/bin:/sbin; /root/chroot-build.sh"

# Unmount (reverse order of mount)
[[ -n "${BIND_BIN:-}" ]] && umount -v "$LFS/lib64" 2>/dev/null || true
[[ -n "${BIND_BIN:-}" ]] && umount -v "$LFS/lib" 2>/dev/null || true
[[ -n "${BIND_BIN:-}" ]] && umount -v "$LFS/bin" 2>/dev/null || true
umount -v "$LFS/dev/pts" 2>/dev/null || true
umount -v "$LFS/dev" 2>/dev/null || true
umount -v "$LFS/proc" 2>/dev/null || true
umount -v "$LFS/sys" 2>/dev/null || true
umount -v "$LFS/run" 2>/dev/null || true
echo "Chroot build phase complete. Next: 05-build-kernel.sh"
exit 0
