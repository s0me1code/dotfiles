#!/usr/bin/env bash
#
# habit-daemon.sh — Hyprland socket2 listener for automatic habit clock-in/out.
#
# Architecture:
#   socket2 → event router → handler functions → state reducer → habit-clock.py → Habits.org
#
# References:
#   - https://wiki.hyprland.org/IPC/
#   - https://github.com/mgjules/hyprwatch (clean Go socket2 listener)
#   - https://github.com/zzampax/hyprland-workspaces-ipc (state reducer pattern)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOCK_PY="$SCRIPT_DIR/habit-clock.py"
STATE_DIR="$SCRIPT_DIR/state"
LOG_FILE="$STATE_DIR/daemon.log"
STATE_FILE="$STATE_DIR/active_task"

export HABIT_CONFIG_DIR="$SCRIPT_DIR"

last_task=""
last_title=""

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

log() {
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] $*" >> "$LOG_FILE"
}

# ---------------------------------------------------------------------------
# Socket discovery
# ---------------------------------------------------------------------------

discover_socket() {
    local socket=""
    local attempts=0
    local max_attempts=30

    if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        socket="${XDG_RUNTIME_DIR}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
        if [[ -S "$socket" ]]; then
            echo "$socket"
            return 0
        fi
    fi

    while (( attempts < max_attempts )); do
        local hypr_pid
        hypr_pid="$(pgrep -x Hyprland 2>/dev/null | head -1)" || true
        if [[ -n "$hypr_pid" ]] && [[ -r "/proc/$hypr_pid/environ" ]]; then
            local sig
            sig="$(tr '\0' '\n' < "/proc/$hypr_pid/environ" | grep '^HYPRLAND_INSTANCE_SIGNATURE=' | cut -d= -f2)"
            if [[ -n "$sig" ]]; then
                export HYPRLAND_INSTANCE_SIGNATURE="$sig"
                socket="${XDG_RUNTIME_DIR}/hypr/${sig}/.socket2.sock"
                if [[ -S "$socket" ]]; then
                    echo "$socket"
                    return 0
                fi
            fi
        fi
        (( attempts++ ))
        sleep 1
    done

    return 1
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

clock_py() {
    python3 "$CLOCK_PY" "$@"
}

get_active_title() {
    local json
    json="$(hyprctl activewindow -j 2>/dev/null)" || return 1
    echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('title',''))" 2>/dev/null
}

notify() {
    local summary="$1"
    local body="$2"
    notify-send --app-name="Habit Tracker" --urgency=low "$summary" "$body" 2>/dev/null || true
}

get_today_for_task() {
    clock_py today "$1" 2>/dev/null | sed 's/^  //'
}

# ---------------------------------------------------------------------------
# State reducer: only act when the matched task actually changes
# ---------------------------------------------------------------------------

evaluate_title() {
    local title="$1"
    local matched
    matched="$(clock_py match "$title")"

    if [[ "$matched" == "$last_task" ]]; then
        return
    fi

    if [[ -n "$last_task" ]]; then
        clock_py clockout
        local duration
        duration="$(clock_py today "$last_task" 2>/dev/null | sed 's/^  //')"
        log "clockout: $last_task"
        notify "⏹ Clocked Out" "<b>$last_task</b>\nSession total: $duration"
    fi

    if [[ -n "$matched" ]]; then
        clock_py clockin "$matched"
        local today_total
        today_total="$(get_today_for_task "$matched")"
        log "clockin: $matched (title: $title)"
        notify "⏱ Clocking In" "<b>$matched</b>\nToday so far: $today_total"
    fi

    last_task="$matched"
    last_title="$title"
}

# ---------------------------------------------------------------------------
# Handler functions (one per event type)
# ---------------------------------------------------------------------------

handle_activewindow() {
    local data="$1"
    local title="${data#*,}"
    evaluate_title "$title"
}

handle_closewindow() {
    sleep 0.2
    local title
    title="$(get_active_title)" || return
    evaluate_title "$title"
}

handle_lock() {
    if [[ -n "$last_task" ]]; then
        clock_py clockout
        log "clockout (lock): $last_task"
        notify "⏹ Clocked Out" "<b>$last_task</b>\n(screen locked)"
    fi
    last_task=""
    last_title=""
}

handle_unlock() {
    sleep 1
    local title
    title="$(get_active_title)" || return
    evaluate_title "$title"
}

# ---------------------------------------------------------------------------
# Cleanup on exit
# ---------------------------------------------------------------------------

cleanup() {
    log "daemon stopping, running clockout"
    clock_py clockout 2>/dev/null || true
    last_task=""
    exit 0
}

trap cleanup SIGTERM SIGINT

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

mkdir -p "$STATE_DIR"

log "daemon starting"

if [[ -f "$STATE_FILE" ]]; then
    log "found stale state file from previous run, clocking out"
    clock_py clockout 2>/dev/null || true
fi

SOCKET="$(discover_socket)" || {
    log "FATAL: could not find Hyprland socket2 after 30s"
    echo "error: could not find Hyprland socket2" >&2
    exit 1
}
log "connected to socket: $SOCKET"

# Evaluate the currently focused window at startup
startup_title="$(get_active_title 2>/dev/null)" || true
if [[ -n "$startup_title" ]]; then
    evaluate_title "$startup_title"
fi

socat -U - "UNIX-CONNECT:$SOCKET" | while IFS= read -r line; do
    EVENT="${line%%>>*}"
    DATA="${line#*>>}"

    case "$EVENT" in
        activewindow)   handle_activewindow "$DATA" ;;
        closewindow)    handle_closewindow "$DATA" ;;
        lockscreen)     handle_lock ;;
        unlockscreen)   handle_unlock ;;
        *)              continue ;;
    esac
done

log "socat stream ended, exiting"
clock_py clockout 2>/dev/null || true
