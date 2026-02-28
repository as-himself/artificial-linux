#!/bin/bash
# Artificial Linux - SLM Guard: coordinate between system logs and BPF LSM gatekeeper
# Monitors journal (or syslog), asks SLM if line indicates threat; if LOCK, updates BPF map.
# Run as systemd service slm-guard.service (root or CAP_SYS_ADMIN).

MAP_NAME="${SLM_CONTROL_MAP:-control_map}"
SLM_API="${SLM_API:-http://127.0.0.1:8080/completion}"
LOG_DIR="/var/log/ai-fabric"
BATCH_INTERVAL="${SLM_GUARD_BATCH_SEC:-30}"

mkdir -p "$LOG_DIR"
exec >> "$LOG_DIR/guard.log" 2>&1

echo "SLM Guard started. Monitoring for anomalies..."

# Prefer systemd journal; fallback to syslog
if command -v journalctl &>/dev/null; then
    tail_source="journalctl -f -n 0 -o short-unix"
else
    tail_source="tail -F /var/log/syslog"
fi

batch=""
last_send=0

while read -r line; do
    batch="$batch
$line"
    now=$(date +%s)
    if [[ $(( now - last_send )) -ge $BATCH_INTERVAL ]] && [[ -n "$batch" ]]; then
        PROMPT="System log excerpt (answer ONLY 'LOCK' if critical security threat, otherwise 'PASS'): $batch"
        RESPONSE=$(curl -s -X POST "$SLM_API" \
            -H "Content-Type: application/json" \
            -d "{\"prompt\": $(echo "$PROMPT" | jq -Rs .), \"n_predict\": 5}" 2>/dev/null | jq -r '.content // empty' 2>/dev/null) || RESPONSE=""
        if [[ "$RESPONSE" == *"LOCK"* ]]; then
            echo "ALERT: SLM detected threat. Locking down."
            MAP_ID=$(bpftool map show name "$MAP_NAME" 2>/dev/null | head -1 | awk -F: '{print $1}')
            if [[ -n "$MAP_ID" ]]; then
                bpftool map update id "$MAP_ID" key 0 0 0 0 value 1 0 0 0 2>/dev/null && \
                    logger "BPF_LSM: System locked down by SLM decision." || true
            fi
        fi
        batch=""
        last_send=$now
    fi
done < <($tail_source 2>/dev/null || tail -F /var/log/syslog 2>/dev/null)
