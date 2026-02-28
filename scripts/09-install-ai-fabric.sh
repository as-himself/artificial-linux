#!/usr/bin/env bash
# Artificial Linux - Phase 9: Install AI fabric (systemd, ask, shell, eBPF, slm-guard)
# Run on LFS system. Expects PROJECT_ROOT or runs from script dir; copies from src/ and systemd/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${ALFS_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
CONFIG_DIR="$PROJECT_ROOT/config"
SRC_DIR="$PROJECT_ROOT/src"
SYSTEMD_DIR="$PROJECT_ROOT/systemd"
LOG_DIR="${ALFS_LOG_DIR:-/var/log/alfs}"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/09-install-ai-fabric.log"
exec 1> >(tee -a "$LOG") 2>&1

echo "=== Artificial Linux - Install AI Fabric ($(date)) ==="

[[ -f "$CONFIG_DIR/alfs.conf" ]] && source "$CONFIG_DIR/alfs.conf"

# /etc/ai-fabric
mkdir -p /etc/ai-fabric
if [[ -f "$SRC_DIR/ai-fabric/system-prompt.txt" ]]; then
    cp -v "$SRC_DIR/ai-fabric/system-prompt.txt" /etc/ai-fabric/
fi
# Optional ask.conf (longer timeout for CPU-only inference)
echo "# ask binary config (optional)" > /etc/ai-fabric/ask.conf
echo "ASK_URL=http://127.0.0.1:8080" >> /etc/ai-fabric/ask.conf
echo "ASK_TIMEOUT=180" >> /etc/ai-fabric/ask.conf

# systemd units
mkdir -p /etc/systemd/system
for f in "$SYSTEMD_DIR"/*.service "$SYSTEMD_DIR"/*.target; do
    [[ -f "$f" ]] && cp -v "$f" /etc/systemd/system/
done
systemctl daemon-reload 2>/dev/null || true

# ask binary: build if src present, else assume already in /usr/local/bin
if [[ -f "$SRC_DIR/ask/ask.cpp" ]]; then
    if command -v cmake &>/dev/null && command -v curl-config &>/dev/null; then
        (cd "$SRC_DIR/ask" && cmake -B build -DCMAKE_INSTALL_PREFIX=/usr/local && cmake --build build && cmake --install build)
    fi
fi
mkdir -p /usr/local/bin
# Install ask if built
if [[ -f "$SRC_DIR/ask/build/ask" ]]; then
    cp -v "$SRC_DIR/ask/build/ask" /usr/local/bin/ask
    chmod +x /usr/local/bin/ask
fi

# slm-guard.sh
if [[ -f "$SRC_DIR/shell/slm-guard.sh" ]]; then
    cp -v "$SRC_DIR/shell/slm-guard.sh" /usr/local/bin/
    chmod +x /usr/local/bin/slm-guard.sh
fi

# slm-launcher (hardware-adaptive llama-server wrapper)
if [[ -f "$SRC_DIR/shell/slm-launcher.sh" ]]; then
    cp -v "$SRC_DIR/shell/slm-launcher.sh" /usr/local/bin/slm-launcher
    chmod +x /usr/local/bin/slm-launcher
fi

# slm-optimize (optional first-boot native rebuild script)
if [[ -f "$SRC_DIR/shell/slm-optimize.sh" ]]; then
    cp -v "$SRC_DIR/shell/slm-optimize.sh" /usr/local/bin/slm-optimize
    chmod +x /usr/local/bin/slm-optimize
fi

# Shell profile and MOTD
mkdir -p /etc/profile.d
if [[ -f "$SRC_DIR/shell/ai-shell-profile.sh" ]]; then
    cp -v "$SRC_DIR/shell/ai-shell-profile.sh" /etc/profile.d/ai-fabric.sh
    chmod 644 /etc/profile.d/ai-fabric.sh
fi
if [[ -f "$SRC_DIR/shell/ai-motd.sh" ]]; then
    cp -v "$SRC_DIR/shell/ai-motd.sh" /etc/profile.d/ai-motd.sh
    chmod 644 /etc/profile.d/ai-motd.sh
fi
if [[ -f "$SRC_DIR/shell/ai-make" ]]; then
    cp -v "$SRC_DIR/shell/ai-make" /usr/local/bin/ai-make
    chmod +x /usr/local/bin/ai-make
fi

# eBPF: install compiled .o and user-space monitor if present
mkdir -p /usr/local/lib/bpf /usr/local/bin
if [[ -f "$SRC_DIR/ebpf/monitor.bpf.o" ]]; then
    cp -v "$SRC_DIR/ebpf/monitor.bpf.o" /usr/local/lib/bpf/
fi
if [[ -f "$SRC_DIR/ebpf/gatekeeper.bpf.o" ]]; then
    cp -v "$SRC_DIR/ebpf/gatekeeper.bpf.o" /usr/local/lib/bpf/
fi
if [[ -f "$SRC_DIR/ebpf/monitor" ]]; then
    cp -v "$SRC_DIR/ebpf/monitor" /usr/local/bin/ebpf-monitor
    chmod +x /usr/local/bin/ebpf-monitor
fi

# Log dir for slm-guard
mkdir -p /var/log/ai-fabric

# Enable AI fabric target (optional; user can enable manually)
systemctl enable ai-fabric.target 2>/dev/null || true
echo "Enable with: systemctl enable --now slm-server.service; systemctl enable --now ai-fabric.target"
echo "AI fabric install complete. Next: 10-create-iso.sh (branding first)."
exit 0
