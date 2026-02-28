#!/usr/bin/env bash
# Artificial Linux - Phase 3: Build LFS cross-toolchain (LFS Ch 5-6)
# Run as user lfs with LFS set (e.g. after 02-create-lfs-user.sh).
# This script orchestrates the toolchain build; full automation requires
# LFS wget-list and package list. Here we define the sequence and key steps.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$PROJECT_ROOT/config"
LOG_DIR="${ALFS_LOG_DIR:-/var/log/alfs}"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/03-build-toolchain.log"
exec 1> >(tee -a "$LOG") 2>&1

echo "=== Artificial Linux - Build Toolchain ($(date)) ==="

[[ -f "$CONFIG_DIR/alfs.conf" ]] && source "$CONFIG_DIR/alfs.conf"
export LFS="${LFS:-/mnt/lfs}"
export LFS_TGT=$(uname -m)-lfs-linux-gnu
export PATH="/usr/bin:/bin"
[[ -d "$LFS/tools/bin" ]] && export PATH="$LFS/tools/bin:$PATH"
export CONFIG_SITE="$LFS/usr/share/config.site"
mkdir -p "$LFS/sources" "$LFS/tools"
cd "$LFS/sources"

# Helper: download if not present
download() {
    local url="$1" name="${2:-}"
    [[ -z "$name" ]] && name=$(basename "$url")
    [[ -f "$name" ]] && return 0
    echo "Downloading $name..."
    wget -q -O "$name" "$url" || curl -L -o "$name" "$url" || return 1
    return 0
}

# Helper: extract tarball
extract() {
    local tarball="$1"
    [[ ! -f "$tarball" ]] && return 1
    local dir="${tarball%.tar.*}"
    dir="${dir%.tgz}"
    [[ -d "$dir" ]] && rm -rf "$dir"
    tar xf "$tarball"
    echo "$dir"
}

# Check: we need key packages. If LFS wget-list is available, use it.
WGET_LIST="${ALFS_WGET_LIST:-}"
if [[ -n "$WGET_LIST" ]] && [[ -f "$WGET_LIST" ]]; then
    echo "Using wget-list: $WGET_LIST"
    wget -q -i "$WGET_LIST" -P "$LFS/sources" || true
fi

# Download key packages from alfs.conf URLs
download "$URL_BINUTILS" "binutils-${BINUTILS_VER}.tar.xz" || true
download "$URL_GCC" "gcc-${GCC_VER}.tar.xz" || true
download "$URL_GLIBC" "glibc-${GLIBC_VER}.tar.xz" || true
download "$URL_LINUX" "linux-${LINUX_VER}.tar.xz" || true

# Build order (simplified; full LFS has exact configure/make steps)
# 5.4 Binutils Pass 1
if [[ -f "binutils-${BINUTILS_VER}.tar.xz" ]]; then
    dir=$(extract "binutils-${BINUTILS_VER}.tar.xz")
    [[ -n "$dir" ]] && pushd "$dir" && {
        mkdir -p build && cd build
        ../configure --prefix=$LFS/tools --with-sysroot=$LFS --target=$LFS_TGT --disable-nls --disable-werror
        make ${MAKEFLAGS:-}
        make install
        popd
    }
fi

# 5.5 GCC Pass 1 (requires GMP, MPFR, MPC - use --with-*-build or bundled)
# 5.6 Linux API Headers
if [[ -f "linux-${LINUX_VER}.tar.xz" ]]; then
    dir=$(extract "linux-${LINUX_VER}.tar.xz")
    [[ -n "$dir" ]] && pushd "$dir" && {
        make mrproper
        make headers
        find usr/include -type f ! -name '*.h' -delete
        cp -rv usr/include "$LFS/usr"
        popd
    }
fi

# 5.7 Glibc
# 5.8 Libstdc++ (from GCC)
# 5.9 Binutils Pass 2
# 5.10 GCC Pass 2
# Then Ch 6: M4, Ncurses, Bash, Coreutils, etc.

echo "Toolchain build sequence started. For a complete automated build, use LFS wget-list and run each chapter step from the LFS book, or use jhalfs/ALFS."
echo "Next: enter chroot and run 04-build-chroot.sh (from host: sudo chroot \$LFS /tools/bin/bash -c '...')."
exit 0
