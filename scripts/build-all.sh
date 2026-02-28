#!/usr/bin/env bash
# Artificial Linux - Master build orchestrator
# Runs phases 00-10 in order; tracks state for resume. Set ALFS_PROJECT_ROOT and ALFS_BUILD_DIR.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${ALFS_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
BUILD_DIR="${ALFS_BUILD_DIR:-$PROJECT_ROOT/build}"
LOG_DIR="${ALFS_LOG_DIR:-$BUILD_DIR/log}"
STATE_FILE="$BUILD_DIR/.alfs-state"
export ALFS_PROJECT_ROOT="$PROJECT_ROOT"
export ALFS_BUILD_DIR="$BUILD_DIR"
export ALFS_LOG_DIR="$LOG_DIR"

mkdir -p "$BUILD_DIR" "$LOG_DIR"
# When running as root, allow project owner to write logs (so non-root can run/resume later)
if [[ $EUID -eq 0 ]] && [[ -d "$PROJECT_ROOT" ]]; then
    OWNER=$(stat -c '%u:%g' "$PROJECT_ROOT" 2>/dev/null || true)
    [[ -n "$OWNER" ]] && chown -R "$OWNER" "$BUILD_DIR" 2>/dev/null || true
fi

# Auto-detect if running inside VM (skip phase 00 if so)
# Phase 00 is only for setting up QEMU from macOS host
INSIDE_VM=0
if [[ -f /proc/cpuinfo ]] && grep -qi "QEMU\|KVM\|VirtualBox\|VMware" /proc/cpuinfo 2>/dev/null; then
    INSIDE_VM=1
elif [[ -d /sys/class/dmi/id ]] && grep -qi "QEMU\|VirtualBox\|VMware" /sys/class/dmi/id/* 2>/dev/null; then
    INSIDE_VM=1
fi

# Phases in order (script name : state key)
PHASES=(
    "00-setup-vm.sh:phase00"
    "01-prepare-host.sh:phase01"
    "02-create-lfs-user.sh:phase02"
    "03-build-toolchain.sh:phase03"
    "04-build-chroot.sh:phase04"
    "05-build-kernel.sh:phase05"
    "06-configure-boot.sh:phase06"
    "07-build-blfs.sh:phase07"
    "08-build-inference.sh:phase08"
    "09-install-ai-fabric.sh:phase09"
    "10-create-iso.sh:phase10"
)

# Skip phase 00 if inside VM (it's only for macOS host to setup QEMU)
if [[ $INSIDE_VM -eq 1 ]] && [[ -z "${ALFS_FROM:-}" ]]; then
    echo "Detected VM environment. Skipping phase 00 (VM setup)."
    export ALFS_FROM="01"
fi

get_state() {
    local key="$1"
    [[ -f "$STATE_FILE" ]] && grep -E "^${key}=" "$STATE_FILE" 2>/dev/null | cut -d= -f2- || echo ""
}

set_state() {
    local key="$1" val="${2:-done}"
    local tmp="$STATE_FILE.tmp"
    if [[ -f "$STATE_FILE" ]]; then
        grep -vE "^${key}=" "$STATE_FILE" 2>/dev/null > "$tmp" || true
    else
        : > "$tmp"
    fi
    echo "${key}=${val}" >> "$tmp"
    mv "$tmp" "$STATE_FILE"
}

run_phase() {
    local script="$1" state_key="$2"
    local path="$SCRIPT_DIR/$script"
    if [[ ! -f "$path" ]]; then
        echo "Skip (not found): $script"
        return 0
    fi
    # ALFS_FORCE=NN re-runs phase NN even if already done (e.g. ALFS_FORCE=10)
    if [[ -n "${ALFS_FORCE:-}" ]] && [[ "$script" == "${ALFS_FORCE}"* ]]; then
        echo "Re-running (ALFS_FORCE=$ALFS_FORCE): $script"
        if [[ -f "$STATE_FILE" ]]; then
            grep -vE "^${state_key}=" "$STATE_FILE" 2>/dev/null > "${STATE_FILE}.tmp" || true
            mv "${STATE_FILE}.tmp" "$STATE_FILE" 2>/dev/null || true
        fi
    fi
    if [[ "$(get_state "$state_key")" == "done" ]]; then
        echo "Skip (already done): $script"
        return 0
    fi
    echo "=== Running: $script ==="
    if bash "$path"; then
        set_state "$state_key" "done"
        echo "Done: $script"
    else
        echo "Failed: $script (state not updated; re-run to resume)"
        return 1
    fi
    return 0
}

# Optional: run from phase (e.g. ALFS_FROM=05). Phase 00 (VM setup) is usually run on host separately.
FROM="${ALFS_FROM:-00}"
STARTED=0

main() {
    echo "=== Artificial Linux - Build All ==="
    echo "Project: $PROJECT_ROOT"
    echo "Build:   $BUILD_DIR"
    echo "Log:     $LOG_DIR"
    echo "Resume from: $FROM (set ALFS_FROM=NN to start from phase NN; set ALFS_FORCE=NN to re-run phase NN)"
    echo ""

    for entry in "${PHASES[@]}"; do
        script="${entry%%:*}"
        state_key="${entry##*:}"
        # Skip until we reach the requested FROM phase (match script prefix e.g. 01-prepare -> FROM=01)
        if [[ "$script" == "$FROM"* ]]; then
            STARTED=1
        fi
        if [[ "$STARTED" -eq 1 ]]; then
            run_phase "$script" "$state_key" || exit 1
        fi
    done

    echo ""
    echo "Build complete. State: $STATE_FILE"
}

main "$@"
