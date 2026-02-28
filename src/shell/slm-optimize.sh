#!/usr/bin/env bash
# Artificial Linux - First-boot optimizer: rebuild llama.cpp with native CPU flags
# Run once (e.g. via slm-optimize.service). Touches a sentinel so it never runs again.
# Enable with: systemctl enable --now slm-optimize.service

set -euo pipefail

SENTINEL="/var/lib/llm/slm-optimized"
LLAMACPP_DIR="${ALFS_BUILD_SRC:-/usr/src}/llama.cpp"
LOG_TAG="slm-optimize"

log() { echo "$*" | logger -t "$LOG_TAG" 2>/dev/null || true; }

if [[ -f "$SENTINEL" ]]; then
    log "Already optimized (sentinel present). Skipping."
    exit 0
fi

mkdir -p /var/lib/llm

if [[ ! -d "$LLAMACPP_DIR" ]] || [[ ! -f "$LLAMACPP_DIR/CMakeLists.txt" ]]; then
    log "llama.cpp source not found at $LLAMACPP_DIR. Skip native rebuild."
    exit 0
fi
if ! command -v cmake &>/dev/null || ! command -v make &>/dev/null; then
    log "cmake or make not available. Skip native rebuild."
    exit 0
fi

log "Rebuilding llama.cpp with native CPU flags..."
cd "$LLAMACPP_DIR"
unset CFLAGS CXXFLAGS
rm -rf build
mkdir -p build
cd build
# Use -march=native so the binary is optimized for this machine's CPU (AVX2/FMA etc. if present).
cmake .. \
  -DGGML_NATIVE=ON \
  -DGGML_BLAS=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DCMAKE_C_FLAGS="-O2 -march=native" \
  -DCMAKE_CXX_FLAGS="-O2 -march=native"
make ${MAKEFLAGS:-}
make install
touch "$SENTINEL"
log "Native rebuild complete. Sentinel created at $SENTINEL"
exit 0
