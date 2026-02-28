#!/usr/bin/env bash
# Artificial Linux - Phase 8: Build llama.cpp and deploy quantized model
# Run on LFS system with BLFS packages (cmake, OpenBLAS, etc.). Expects GGUF at
# ALFS_GGUF or /tmp/ (e.g. tinyllama-1.1b-chat-v1.0-Q5_K_M.gguf or granite-4.0-micro-Q5_K_M.gguf).

set -euo pipefail

# useradd, groupadd, etc. live in /usr/sbin
export PATH="/usr/sbin:/sbin:/usr/bin:/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$PROJECT_ROOT/config"
LOG_DIR="${ALFS_LOG_DIR:-/var/log/alfs}"
BUILD_SRC="${ALFS_BUILD_SRC:-/usr/src}"
LLAMACPP_DIR="$BUILD_SRC/llama.cpp"
MODEL_DEST="/usr/share/models"
# Default: look for TinyLlama or Granite GGUF in /tmp
GGUF_SRC="${ALFS_GGUF:-}"
if [[ -z "$GGUF_SRC" ]]; then
    for f in /tmp/tinyllama-1.1b-chat-v1.0-Q5_K_M.gguf /tmp/granite-4.0-micro-Q5_K_M.gguf /tmp/*-Q5_K_M.gguf; do
        [[ -f "$f" ]] && GGUF_SRC="$f" && break
    done
fi
[[ -z "$GGUF_SRC" ]] && GGUF_SRC="/tmp/artificial-linux-slm-Q5_K_M.gguf"
MODEL_FILENAME=$(basename "$GGUF_SRC")
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/08-build-inference.log"
exec 1> >(tee -a "$LOG") 2>&1

echo "=== Artificial Linux - Build Inference ($(date)) ==="

[[ -f "$CONFIG_DIR/alfs.conf" ]] && source "$CONFIG_DIR/alfs.conf"
export LFS="${LFS:-/}"

# Create llm-user (non-login, for running inference service)
if ! getent passwd llm-user &>/dev/null; then
    useradd -r -s /usr/sbin/nologin -d /var/lib/llm -c "SLM inference service" llm-user
    mkdir -p /var/lib/llm
    chown llm-user:llm-user /var/lib/llm
fi

mkdir -p "$MODEL_DEST"
chown llm-user:llm-user "$MODEL_DEST" 2>/dev/null || true

# Download llama.cpp (use tarball: Git built in 07 may lack HTTPS support)
LLAMACPP_TAR="$BUILD_SRC/llama.cpp-master.tar.gz"
if [[ ! -d "$LLAMACPP_DIR" ]] || [[ ! -f "$LLAMACPP_DIR/CMakeLists.txt" ]]; then
    echo "Downloading llama.cpp..."
    mkdir -p "$BUILD_SRC"
    if [[ -d "$LLAMACPP_DIR" ]]; then rm -rf "$LLAMACPP_DIR"; fi
    (cd "$BUILD_SRC" && curl -sL -o llama.cpp-master.tar.gz "https://github.com/ggerganov/llama.cpp/archive/refs/heads/master.tar.gz" && tar xzf llama.cpp-master.tar.gz && mv llama.cpp-master llama.cpp && rm -f llama.cpp-master.tar.gz)
fi
cd "$LLAMACPP_DIR"

# pkg-config required by llama.cpp CMake for BLAS; install if missing (e.g. minimal BLFS)
if ! command -v pkg-config &>/dev/null; then
    for try in apt-get dnf yum; do
        if command -v "$try" &>/dev/null; then
            echo "Installing pkg-config for llama.cpp build..."
            ("$try" install -y pkg-config 2>/dev/null) || true
            break
        fi
    done
fi

# Build llama.cpp: ultra-portable baseline (no SSE4.2/AVX/FMA/etc.) and static ggml
# so it runs on any x86-64 CPU and does not depend on distro libggml packages.
# Unset env CFLAGS/CXXFLAGS so CMake's own detection does not enable host-specific extensions.
unset CFLAGS CXXFLAGS
rm -rf build
mkdir -p build
cd build
cmake .. \
  -DGGML_NATIVE=OFF \
  -DGGML_SSE42=OFF \
  -DGGML_AVX=OFF \
  -DGGML_AVX_VNNI=OFF \
  -DGGML_AVX2=OFF \
  -DGGML_BMI2=OFF \
  -DGGML_FMA=OFF \
  -DGGML_F16C=OFF \
  -DGGML_AVX512=OFF \
  -DGGML_AVX512_VBMI=OFF \
  -DGGML_AVX512_VNNI=OFF \
  -DGGML_LASX=OFF \
  -DGGML_LSX=OFF \
  -DGGML_BLAS=OFF \
  -DGGML_CPU_ALL_VARIANTS=OFF \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_STATIC=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DCMAKE_C_FLAGS="-O2 -march=x86-64 -mtune=generic" \
  -DCMAKE_CXX_FLAGS="-O2 -march=x86-64 -mtune=generic"
make ${MAKEFLAGS:-}
make install

# Copy model to system (install as artificial-linux-slm.gguf so systemd unit stays fixed)
if [[ -f "$GGUF_SRC" ]]; then
    cp -v "$GGUF_SRC" "$MODEL_DEST/artificial-linux-slm.gguf"
    chown llm-user:llm-user "$MODEL_DEST/artificial-linux-slm.gguf"
else
    echo "GGUF not found at $GGUF_SRC. Copy $MODEL_FILENAME (or any *-Q5_K_M.gguf) to $MODEL_DEST/artificial-linux-slm.gguf manually."
fi

# Verify
if [[ -f "$MODEL_DEST/artificial-linux-slm.gguf" ]]; then
    echo "Verifying model..."
    llama-cli -m "$MODEL_DEST/artificial-linux-slm.gguf" -p "Hello from Artificial Linux" -n 20 --no-display-prompt 2>/dev/null || true
fi

echo "Inference engine build complete. Next: 09-install-ai-fabric.sh"
exit 0
