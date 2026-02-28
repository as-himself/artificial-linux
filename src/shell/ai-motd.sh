#!/bin/bash
# Artificial Linux - AI-generated MOTD (Message of the Day)
# Source from /etc/profile.d/ai-motd.sh (run on login)
# Pipes system stats to SLM for a natural-language greeting

[[ -n "$PS1" ]] || return 0
# Only once per login
[[ -n "$AL_MOTD_SHOWN" ]] && return 0
export AL_MOTD_SHOWN=1

if ! command -v ask &>/dev/null; then return 0; fi

STATS=$(uptime 2>/dev/null; echo "---"; df -h / 2>/dev/null | tail -1; echo "---"; free -h 2>/dev/null | head -2)
ask "Summarize this system status in one friendly sentence for the user logging in: $STATS" 80 2>/dev/null || true
