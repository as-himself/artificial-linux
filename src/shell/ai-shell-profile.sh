# Artificial Linux - AI Shell Integration
# Source from /etc/profile.d/ai-fabric.sh
# Provides: PROMPT_COMMAND error analysis, ask alias, PS1

# Only run in interactive bash
[[ -n "$PS1" ]] || return 0
[[ -n "$BASH_VERSION" ]] || return 0

# Apply ask client config (URL, timeout) so CPU-only inference has time to respond
[[ -f /etc/ai-fabric/ask.conf ]] && source /etc/ai-fabric/ask.conf 2>/dev/null
export ASK_URL ASK_TIMEOUT 2>/dev/null

# AI Error Analysis: when last command failed, ask SLM for a brief fix
analyze_error() {
    local EXIT_CODE=$?
    if [[ $EXIT_CODE -ne 0 ]]; then
        local LAST_CMD
        LAST_CMD=$(history 1 2>/dev/null | sed 's/^[ ]*[0-9]*[ ]*//')
        echo -e "\033[31m[!] Command failed with code $EXIT_CODE\033[0m"
        echo -n "AI Suggestion: "
        if command -v ask &>/dev/null; then
            ask "The command '$LAST_CMD' failed on Artificial Linux. Briefly explain why and suggest the correct command." 64 2>/dev/null || echo "(SLM unavailable)"
        else
            echo "(ask binary not found)"
        fi
    fi
}

export PROMPT_COMMAND="analyze_error"

# Alias for quick queries
alias helpme='ask'
alias ask-ai='ask'

# Custom prompt: user@artificial-linux:path$
export PS1="\[\033[32m\]\u@artificial-linux\[\033[0m\]:\[\033[34m\]\w\[\033[0m\]\$ "
