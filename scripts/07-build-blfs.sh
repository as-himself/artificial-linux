#!/usr/bin/env bash
# Artificial Linux - Phase 7: BLFS extensions (cmake, git, curl, clang, libbpf, etc.)
# Run on finished LFS system (or in chroot). Installs packages required for AI fabric.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$PROJECT_ROOT/config"
LOG_DIR="${ALFS_LOG_DIR:-/var/log/alfs}"
BLFS_SRC="${BLFS_SRC:-/usr/src/blfs}"
mkdir -p "$LOG_DIR" "$BLFS_SRC"
LOG="$LOG_DIR/07-build-blfs.log"
exec 1> >(tee -a "$LOG") 2>&1

echo "=== Artificial Linux - Build BLFS ($(date)) ==="

[[ -f "$CONFIG_DIR/alfs.conf" ]] && source "$CONFIG_DIR/alfs.conf"
export LFS="${LFS:-/mnt/lfs}"
ROOT="${LFS:-/}"
[[ "$LFS" == "/" ]] || [[ -d "$LFS/usr" ]] && ROOT="$LFS"
cd "$BLFS_SRC"

# BLFS package versions (stable)
CMAKE_VER=3.30.0
GIT_VER=2.47.1
CURL_VER=8.14.0
PYTHON_VER=3.13.7
OPENBLAS_VER=0.3.28
LLVM_VER=18.1.8
LIBBPF_VER=1.4.0
JQ_VER=1.7.1

download() {
    local url="$1" name="${2:-}"
    [[ -z "$name" ]] && name=$(basename "$url")
    [[ -f "$name" ]] && return 0
    wget -q -O "$name" "$url" || curl -L -o "$name" "$url" || return 1
    return 0
}

extract() {
    local tarball="$1"
    [[ ! -f "$tarball" ]] && return 1
    local dir="${tarball%.tar.*}"
    dir="${dir%.tgz}"
    [[ -d "$dir" ]] && rm -rf "$dir"
    tar xf "$tarball"
    echo "$dir"
}

# CMake
echo "Building CMake..."
download "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VER}/cmake-${CMAKE_VER}.tar.gz" || \
    download "https://cmake.org/files/v3.30/cmake-${CMAKE_VER}.tar.gz" || true
if [[ -f "cmake-${CMAKE_VER}.tar.gz" ]]; then
    dir=$(extract "cmake-${CMAKE_VER}.tar.gz")
    [[ -n "$dir" ]] && pushd "$dir" && {
        ./bootstrap --prefix=/usr -- -DCMAKE_BUILD_TYPE=Release
        make ${MAKEFLAGS:-} && make install
        popd
    }
fi

# Git
echo "Building Git..."
download "https://www.kernel.org/pub/software/scm/git/git-${GIT_VER}.tar.xz" || true
if [[ -f "git-${GIT_VER}.tar.xz" ]]; then
    dir=$(extract "git-${GIT_VER}.tar.xz")
    [[ -n "$dir" ]] && pushd "$dir" && {
        ./configure --prefix=/usr
        make ${MAKEFLAGS:-} NO_GETTEXT=1 && make install NO_GETTEXT=1
        popd
    }
fi

# cURL + libcurl
echo "Building cURL..."
download "https://curl.se/download/curl-${CURL_VER}.tar.xz" || true
if [[ -f "curl-${CURL_VER}.tar.xz" ]]; then
    dir=$(extract "curl-${CURL_VER}.tar.xz")
    [[ -n "$dir" ]] && pushd "$dir" && {
        ./configure --prefix=/usr --with-openssl --without-libpsl
        make ${MAKEFLAGS:-} && make install
        popd
    }
fi

# OpenBLAS (for llama.cpp CPU inference)
echo "Building OpenBLAS..."
download "https://github.com/OpenMathLib/OpenBLAS/releases/download/v${OPENBLAS_VER}/OpenBLAS-${OPENBLAS_VER}.tar.gz" || true
if [[ -f "OpenBLAS-${OPENBLAS_VER}.tar.gz" ]]; then
    dir=$(extract "OpenBLAS-${OPENBLAS_VER}.tar.gz")
    [[ -n "$dir" ]] && pushd "$dir" && {
        make ${MAKEFLAGS:-} && make PREFIX=/usr install
        popd
    }
fi

# jq (JSON for shell scripts)
echo "Building jq..."
download "https://github.com/jqlang/jq/releases/download/jq-${JQ_VER}/jq-${JQ_VER}.tar.gz" || true
if [[ -f "jq-${JQ_VER}.tar.gz" ]]; then
    dir=$(extract "jq-${JQ_VER}.tar.gz")
    [[ -n "$dir" ]] && pushd "$dir" && {
        ./configure --prefix=/usr
        make ${MAKEFLAGS:-} && make install
        popd
    }
fi

# Clang/LLVM (for eBPF compilation)
echo "Building LLVM/Clang (this may take a long time)..."
download "https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VER}/llvm-project-${LLVM_VER}.src.tar.xz" || true
if [[ -f "llvm-project-${LLVM_VER}.src.tar.xz" ]]; then
    dir=$(extract "llvm-project-${LLVM_VER}.src.tar.xz")
    [[ -n "$dir" ]] && pushd "$dir" && {
        mkdir -p build && cd build
        cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_PROJECTS="clang" -DCMAKE_INSTALL_PREFIX=/usr ../llvm
        make ${MAKEFLAGS:-} && make install
        popd
    }
fi

# libbpf (user-space BPF library)
echo "Building libbpf..."
download "https://github.com/libbpf/libbpf/archive/refs/tags/v${LIBBPF_VER}.tar.gz" "libbpf-${LIBBPF_VER}.tar.gz" || true
if [[ -f "libbpf-${LIBBPF_VER}.tar.gz" ]]; then
    dir=$(extract "libbpf-${LIBBPF_VER}.tar.gz")
    [[ -n "$dir" ]] && pushd "$dir/src" && {
        make ${MAKEFLAGS:-} BUILD_STATIC_ONLY=n PREFIX=/usr LIBDIR=/usr/lib
        make install PREFIX=/usr LIBDIR=/usr/lib
        popd
    }
fi

# bpftool (from kernel source or libbpf)
if command -v bpftool &>/dev/null; then
    echo "bpftool already available."
else
    echo "Install bpftool from kernel source: make -C tools/bpf/bpftool && make -C tools/bpf/bpftool install"
fi

echo "BLFS build complete. Next: 08-build-inference.sh"
exit 0
