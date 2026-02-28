#!/usr/bin/env bash
# Artificial Linux - Phase 1: Prepare host system for LFS build (LFS Ch 2)
# Run inside the Linux build VM. Verifies/installs required packages.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$PROJECT_ROOT/config"
LOG_DIR="${ALFS_LOG_DIR:-/var/log/alfs}"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/01-prepare-host.log"
exec 1> >(tee -a "$LOG") 2>&1

echo "=== Artificial Linux - Prepare Host ($(date)) ==="

# Load config if present
[[ -f "$CONFIG_DIR/alfs.conf" ]] && source "$CONFIG_DIR/alfs.conf"

# LFS Ch 2: Required packages (minimum versions from LFS book)
REQUIRED=(
    bash:5.2
    binutils:2.42
    bison:3.8
    coreutils:9.0
    gcc:13.0
    g++:13.0
    make:4.4
    patch:2.7
    sed:4.9
    tar:1.35
    xz:5.4
)

check_version() {
    local name="$1" min_ver="$2" cmd="" actual=""
    case "$name" in
        bash)     cmd="bash --version | head -1";;
        binutils) cmd="ld --version | head -1";;   # ld is from binutils
        coreutils) cmd="ls --version 2>/dev/null | head -1 || coreutils --version 2>/dev/null | head -1";;
        g++)      name="g++"; cmd="g++ --version | head -1";;
        *)        cmd="$name --version 2>/dev/null | head -1";;
    esac
    actual=$(eval "$cmd" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1) || true
    if [[ -z "$actual" ]]; then
        echo "MISSING: $name (min $min_ver)"
        return 1
    fi
    # Simple numeric comparison (major.minor)
    local maj_min=$(echo "$min_ver" | cut -d. -f1,2)
    local act_min=$(echo "$actual" | cut -d. -f1,2)
    if [[ "$act_min" < "$maj_min" ]] 2>/dev/null; then
        echo "OLD: $name $actual (need >= $min_ver)"
        return 1
    fi
    echo "OK: $name $actual"
    return 0
}

FAIL=0
for spec in "${REQUIRED[@]}"; do
    name="${spec%%:*}"
    min_ver="${spec#*:}"
    check_version "$name" "$min_ver" || FAIL=1
done

# Helper: run command with sudo only if not root
as_root() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Optional: try to install dependencies on Debian/Ubuntu
if [[ $FAIL -eq 1 ]]; then
    if command -v apt-get &>/dev/null; then
        echo "Attempting to install build dependencies (Debian/Ubuntu)..."
        as_root apt-get update -qq
        as_root apt-get install -y -qq build-essential bison flex gawk texinfo gettext pkg-config \
            binutils coreutils binutils-dev libncurses-dev libelf-dev libssl-dev \
            xorriso grub-pc-bin grub-efi-amd64-bin squashfs-tools busybox-static || true
        FAIL=0
        for spec in "${REQUIRED[@]}"; do
            name="${spec%%:*}"
            min_ver="${spec#*:}"
            check_version "$name" "$min_ver" || FAIL=1
        done
    fi
fi

if [[ $FAIL -eq 1 ]]; then
    echo "Some required packages are missing or too old. See LFS Ch 2."
    exit 1
fi

echo "Host preparation complete."
exit 0
