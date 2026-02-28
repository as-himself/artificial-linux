#!/usr/bin/env bash
# Artificial Linux - SLM server launcher with hardware-adaptive settings
# Probes CPU, RAM, and GPU to build an optimal llama-server invocation.
# Used as ExecStart by slm-server.service; exec's llama-server so it is the main process.

set -euo pipefail

MODEL_PATH="${SLM_MODEL_PATH:-/usr/share/models/artificial-linux-slm.gguf}"
PORT="${SLM_PORT:-8080}"
SYSTEM_PROMPT_FILE="${SLM_SYSTEM_PROMPT:-/etc/ai-fabric/system-prompt.txt}"
LLAMA_SERVER="${LLAMA_SERVER:-/usr/local/bin/llama-server}"

log() {
    # Ensure messages are visible even if journald/logger is unavailable.
    echo "slm-launcher: $*" >&2
    logger -t slm-launcher -- "$*" 2>/dev/null || true
}

# --- CPU: thread count (cap at 8)
NPROC=$(nproc 2>/dev/null || echo 4)
THREADS=$(( NPROC > 8 ? 8 : NPROC ))

# --- RAM: choose ctx-size
MEM_KB=0
if [[ -r /proc/meminfo ]]; then
    MEM_KB=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
fi
MEM_GB=$(( MEM_KB / 1024 / 1024 ))
if [[ "${MEM_GB:-0}" -lt 4 ]]; then
    CTX_SIZE=2048
elif [[ "${MEM_GB:-0}" -lt 8 ]]; then
    CTX_SIZE=4096
else
    CTX_SIZE=8192
fi

# --- GPU: NVIDIA or AMD
GPU_LAYERS=0
if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
    # memory.total in MiB (e.g. 8192 for 8GB)
    VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
    VRAM_MB=${VRAM_MB:-0}
    if [[ "$VRAM_MB" =~ ^[0-9]+$ ]]; then
        if [[ "$VRAM_MB" -ge 8192 ]]; then
            GPU_LAYERS=99
        elif [[ "$VRAM_MB" -ge 4096 ]]; then
            GPU_LAYERS=20
        fi
    fi
    log "NVIDIA GPU detected, VRAM ~${VRAM_MB}MiB, n_gpu_layers=$GPU_LAYERS"
fi
if [[ "$GPU_LAYERS" -eq 0 ]] && command -v rocm-smi &>/dev/null && rocm-smi &>/dev/null; then
    VRAM_KB=$(rocm-smi --showmeminfo vram 2>/dev/null | awk '/^.*VRAM/ { gsub(/[^0-9]/,""); sum+=$0 } END { print sum }')
    VRAM_GB=$(( VRAM_KB / 1024 / 1024 ))
    if [[ "${VRAM_GB:-0}" -ge 8 ]]; then
        GPU_LAYERS=99
    elif [[ "${VRAM_GB:-0}" -ge 4 ]]; then
        GPU_LAYERS=20
    fi
    log "AMD ROCm GPU detected, VRAM ~${VRAM_GB}GB, n_gpu_layers=$GPU_LAYERS"
fi

log "threads=$THREADS ctx_size=$CTX_SIZE gpu_layers=$GPU_LAYERS"

# Build argv for llama-server
ARGV=(
    "$LLAMA_SERVER"
    -m "$MODEL_PATH"
    --port "$PORT"
    --threads "$THREADS"
    --ctx-size "$CTX_SIZE"
)
[[ "$GPU_LAYERS" -gt 0 ]] && ARGV+=(--n-gpu-layers "$GPU_LAYERS")

if [[ ! -x "$LLAMA_SERVER" ]]; then
    log "Fatal: '$LLAMA_SERVER' not found or not executable"
    exit 127
fi
if [[ ! -f "$MODEL_PATH" ]]; then
    log "Fatal: model not found at '$MODEL_PATH'"
    log "Fix: copy a GGUF to /usr/share/models/artificial-linux-slm.gguf (or set SLM_MODEL_PATH)"
    exit 66
fi

exec "${ARGV[@]}"
