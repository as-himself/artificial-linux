#!/usr/bin/env bash
# Artificial Linux - Model conversion: HuggingFace (TinyLlama, Granite, etc.) -> GGUF Q5_K_M
# Run from project root on macOS/Linux. Requires Python 3 and llama.cpp.
# Fixes: numpy<2 for PyTorch/llama.cpp compatibility; auto-detects model and output names.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODEL_DIR="${ALFS_MODEL_DIR:-$PROJECT_ROOT/model}"
BUILD_DIR="${ALFS_BUILD_DIR:-$PROJECT_ROOT/build}"
LLAMACPP_DIR="$BUILD_DIR/llama.cpp"
OUT_DIR="$BUILD_DIR/gguf"
VENV_DIR="$BUILD_DIR/venv-convert"

mkdir -p "$OUT_DIR"

# Detect model basename from config.json (for output filenames)
MODEL_BASENAME="artificial-linux-slm"
if [[ -f "$MODEL_DIR/config.json" ]]; then
    # Use Python to properly read the JSON (no jq dependency on macOS)
    MODEL_TYPE=$(python3 - "$MODEL_DIR/config.json" << 'PYEOF'
import json, sys
try:
    with open(sys.argv[1]) as f:
        cfg = json.load(f)
    print(cfg.get("model_type", cfg.get("architectures", [""])[0]))
except: pass
PYEOF
)
    if [[ "$MODEL_TYPE" == "llama" ]] || [[ "$MODEL_TYPE" == "LlamaForCausalLM" ]]; then
        MODEL_BASENAME="tinyllama-1.1b-chat-v1.0"
    elif [[ "$MODEL_TYPE" == *"Granite"* ]] || [[ "$MODEL_TYPE" == *"granite"* ]]; then
        MODEL_BASENAME="granite-4.0-micro"
    fi
fi
F16_GGUF="$OUT_DIR/${MODEL_BASENAME}-f16.gguf"
Q5_GGUF="$OUT_DIR/${MODEL_BASENAME}-Q5_K_M.gguf"

echo "=== Artificial Linux - Model Conversion ==="
echo "Model dir:   $MODEL_DIR"
echo "Model base:  $MODEL_BASENAME"
echo "Output dir:  $OUT_DIR"
echo ""

# Clone llama.cpp if not present
if [[ ! -d "$LLAMACPP_DIR" ]]; then
    echo "Cloning llama.cpp..."
    git clone --depth 1 https://github.com/ggerganov/llama.cpp.git "$LLAMACPP_DIR"
fi
cd "$LLAMACPP_DIR"
git pull --depth 1 2>/dev/null || true

# Python venv: use numpy<2 to avoid PyTorch/NumPy 2.x incompatibility and torch.uint64 issues
if [[ ! -d "$VENV_DIR" ]]; then
    echo "Creating Python venv for conversion..."
    python3 -m venv "$VENV_DIR"
fi
# shellcheck source=/dev/null
source "$VENV_DIR/bin/activate"
# Ensure numpy<2 and torch>=2.2 (llama.cpp converter uses torch.uint64, added in PyTorch 2.2)
pip install -q "numpy>=1.24.0,<2" --force-reinstall 2>/dev/null || true
pip install -q -r "$PROJECT_ROOT/convert/requirements.txt" 2>/dev/null || true
pip install -q "torch>=2.2.0" --upgrade 2>/dev/null || true

# Check if torch unsigned dtypes exist (PyTorch 2.2+ on some builds); if missing, try downloading pre-quantized GGUF
CONVERT_SCRIPT="$LLAMACPP_DIR/convert_hf_to_gguf.py"
TORCH_UNSIGNED_OK=1
python3 -c "import torch; torch.uint64; torch.uint32; torch.uint16; torch.uint8" 2>/dev/null || TORCH_UNSIGNED_OK=0
if [[ "$TORCH_UNSIGNED_OK" -eq 0 ]] && [[ "$MODEL_BASENAME" == "tinyllama"* ]]; then
    echo "PyTorch build missing unsigned dtypes (uint64, uint32, etc.). Conversion won't work."
    echo "Downloading pre-quantized TinyLlama Q5_K_M from Hugging Face..."
    HF_URL="https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q5_K_M.gguf"
    if [[ ! -f "$Q5_GGUF" ]]; then
        if command -v curl &>/dev/null; then
            curl -L -o "$Q5_GGUF" "$HF_URL" --progress-bar
        elif command -v wget &>/dev/null; then
            wget -O "$Q5_GGUF" "$HF_URL"
        else
            echo "No curl/wget. Download manually: $HF_URL -> $Q5_GGUF"
            exit 1
        fi
        if [[ -f "$Q5_GGUF" ]]; then
            echo "Downloaded pre-quantized model: $Q5_GGUF"
            echo "Skipping conversion and quantization (already Q5_K_M)."
            SKIP_CONVERSION=1
        fi
    else
        echo "Q5_K_M GGUF already exists: $Q5_GGUF. Skipping download."
        SKIP_CONVERSION=1
    fi
fi

# Step 1: Convert HuggingFace model to GGUF (f16) -- skip if we downloaded pre-quantized
if [[ "${SKIP_CONVERSION:-0}" -eq 0 ]]; then
    if [[ ! -f "$F16_GGUF" ]]; then
        echo "Converting $MODEL_DIR to GGUF (f16)..."
        if [[ ! -f "$CONVERT_SCRIPT" ]]; then
            CONVERT_SCRIPT="$LLAMACPP_DIR/convert.py"
        fi
        if [[ ! -f "$CONVERT_SCRIPT" ]]; then
            echo "No convert script found in llama.cpp. Check repo layout."
            exit 1
        fi
        if ! python "$CONVERT_SCRIPT" "$MODEL_DIR" --outfile "$F16_GGUF" --outtype f16; then
            echo "Conversion failed. PyTorch missing unsigned dtypes (uint32/uint64)."
            echo "For TinyLlama, run again and the script will download a pre-quantized GGUF."
            echo "Or download manually from https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF"
            exit 1
        fi
    else
        echo "f16 GGUF already exists: $F16_GGUF"
    fi
else
    echo "Skipping conversion (using pre-quantized GGUF)."
fi

# Build llama.cpp tools (cmake + make) -- only if we're converting (not using pre-downloaded GGUF)
if [[ "${SKIP_CONVERSION:-0}" -eq 0 ]]; then
    if [[ ! -f "$LLAMACPP_DIR/build/bin/llama-quantize" ]] && [[ ! -f "$LLAMACPP_DIR/llama-quantize" ]]; then
        echo "Building llama.cpp..."
        cmake -B build -DGGML_NATIVE=ON -DCMAKE_BUILD_TYPE=Release
        cmake --build build -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
    fi
    QUANTIZE_BIN="$LLAMACPP_DIR/build/bin/llama-quantize"
    [[ ! -f "$QUANTIZE_BIN" ]] && QUANTIZE_BIN="$LLAMACPP_DIR/llama-quantize"
    if [[ ! -f "$QUANTIZE_BIN" ]]; then
        echo "llama-quantize not found. Build failed?"
        exit 1
    fi
else
    echo "Skipping llama.cpp build (using pre-quantized GGUF)."
    QUANTIZE_BIN=""
fi

# Step 2: Quantize to Q5_K_M -- skip if we downloaded pre-quantized
if [[ "${SKIP_CONVERSION:-0}" -eq 0 ]]; then
    if [[ ! -f "$Q5_GGUF" ]]; then
        echo "Quantizing to Q5_K_M..."
        "$QUANTIZE_BIN" "$F16_GGUF" "$Q5_GGUF" Q5_K_M
    else
        echo "Q5_K_M GGUF already exists: $Q5_GGUF"
    fi
elif [[ ! -f "$Q5_GGUF" ]]; then
    echo "Q5_K_M GGUF not found. Download or build failed."
    exit 1
fi

# Step 3: Quick sanity check (if llama-cli was built)
if [[ -f "$Q5_GGUF" ]]; then
    LLAMA_CLI="$LLAMACPP_DIR/build/bin/llama-cli"
    [[ ! -f "$LLAMA_CLI" ]] && LLAMA_CLI="$LLAMACPP_DIR/llama-cli"
    if [[ -f "$LLAMA_CLI" ]]; then
        echo "Verifying model (short run)..."
        "$LLAMA_CLI" -m "$Q5_GGUF" -p "Hello" -n 20 --no-display-prompt 2>/dev/null || true
    fi
fi

echo ""
echo "Done. Quantized model: $Q5_GGUF"
echo "Set ALFS_GGUF=$Q5_GGUF when running 08-build-inference.sh, or copy to /usr/share/models/."
echo "Transfer to VM: scp -P <ssh_port> $Q5_GGUF user@localhost:/tmp/"