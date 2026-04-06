#!/usr/bin/env bash
# cc-restart.sh — Restart Claude Code in tmux
#
# Usage: cc-restart.sh single <session> <project-dir>
#        cc-restart.sh all
#
# First invocation backgrounds itself (nohup+disown) then exits.
# The backgrounded copy (__RUN=1) does the actual work.

set -euo pipefail

LOG="/tmp/cc-restart.log"
RETRIES=3
CLAUDE_CMD="claude --dangerously-skip-permissions --channels plugin:discord@claude-plugins-official"

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOG"; }

# --- helpers ---

# Get the PID that owns a tmux pane
pane_pid() { tmux list-panes -t "$1" -F '#{pane_pid}' 2>/dev/null | head -1; }

# Find claude PID in a session. Claude can be:
#   1) The pane process itself (tmux new-session ... claude)
#   2) A child of the pane's shell (send-keys "claude ...")
find_claude_pid() {
  local session="$1" ppid
  ppid=$(pane_pid "$session") || return 1
  [ -z "$ppid" ] && return 1

  # Check if pane process itself is claude
  local pane_cmd
  pane_cmd=$(ps -p "$ppid" -o comm= 2>/dev/null)
  if [[ "$pane_cmd" == *claude* ]]; then
    echo "$ppid"
    return 0
  fi

  # Check children
  ps -eo pid=,ppid=,args= 2>/dev/null \
    | awk -v p="$ppid" '$2==p && /claude/ {print $1; exit}'
}

# Kill claude in a session, wait for it to die
kill_claude() {
  local session="$1" pid
  pid=$(find_claude_pid "$session")
  [ -z "$pid" ] && { log "[$session] claude not running, skip kill"; return 0; }

  log "[$session] killing claude (pid $pid)"
  kill "$pid" 2>/dev/null || true

  # Wait up to 10s for it to die
  local i
  for i in $(seq 1 10); do
    kill -0 "$pid" 2>/dev/null || { log "[$session] claude exited after ${i}s"; return 0; }
    sleep 1
  done

  # Force kill
  log "[$session] force killing claude"
  kill -9 "$pid" 2>/dev/null || true
  sleep 1
}

# Start claude in a tmux session
start_claude() {
  local session="$1" dir="$2"

  # After killing claude, the session/pane may be gone. Recreate it.
  if ! tmux has-session -t "$session" 2>/dev/null; then
    log "[$session] session gone, creating new one"
    tmux new-session -d -s "$session" -c "$dir"
    sleep 1
  fi

  log "[$session] starting claude in $dir"
  tmux send-keys -t "$session" "cd $dir && $CLAUDE_CMD" Enter
}

# Start claude and poll until it's running
start_and_verify() {
  local session="$1" dir="$2"
  start_claude "$session" "$dir"

  # Poll up to 30s for claude to appear
  local i
  for i in $(seq 1 30); do
    [ -n "$(find_claude_pid "$session")" ] && {
      log "[$session] claude is up (${i}s)"
      return 0
    }
    sleep 1
  done

  log "[$session] claude did not start within 30s"
  tmux capture-pane -t "$session" -p 2>/dev/null | tail -5 >> "$LOG"
  return 1
}

# --- modes ---

do_single() {
  local session="$1" dir="$2"
  log "=== restart single: $session ($dir) ==="

  kill_claude "$session"

  local i
  for i in $(seq 1 "$RETRIES"); do
    log "[$session] attempt $i/$RETRIES"
    if start_and_verify "$session" "$dir"; then
      log "=== restart single: success ==="
      return 0
    fi
    tmux send-keys -t "$session" C-c 2>/dev/null
    sleep 2
  done

  log "=== restart single: FAILED after $RETRIES attempts ==="
  return 1
}

do_all() {
  log "=== restart all: scanning ==="
  local -a sessions=() dirs=()

  local s
  for s in $(tmux list-sessions -F '#{session_name}' 2>/dev/null); do
    if [ -n "$(find_claude_pid "$s")" ]; then
      sessions+=("$s")
      dirs+=("$(tmux list-panes -t "$s" -F '#{pane_current_path}' | head -1)")
    fi
  done

  if [ ${#sessions[@]} -eq 0 ]; then
    log "no active claude sessions found"
    return 1
  fi

  log "found ${#sessions[@]} session(s): ${sessions[*]}"

  # Kill all first
  local i
  for i in "${!sessions[@]}"; do kill_claude "${sessions[$i]}"; done

  # Restart all
  local failed=0
  for i in "${!sessions[@]}"; do
    local attempt
    for attempt in $(seq 1 "$RETRIES"); do
      log "[${sessions[$i]}] attempt $attempt/$RETRIES"
      start_and_verify "${sessions[$i]}" "${dirs[$i]}" && break
      tmux send-keys -t "${sessions[$i]}" C-c 2>/dev/null
      sleep 2
    done
    [ -z "$(find_claude_pid "${sessions[$i]}")" ] && ((failed++))
  done

  [ "$failed" -gt 0 ] && log "$failed session(s) failed"
  log "=== restart all: done ==="
}

# --- entry point ---

MODE="${1:?Usage: cc-restart.sh single <session> <project-dir> | cc-restart.sh all}"

if [ "${__RUN:-}" = "1" ]; then
  log "worker pid=$$ mode=$MODE"
  case "$MODE" in
    single) do_single "$2" "$3" ;;
    all)    do_all ;;
    *)      log "unknown mode: $MODE"; exit 1 ;;
  esac
else
  log "launching background worker (mode=$MODE)..."
  __RUN=1 nohup "$0" "$@" >>"$LOG" 2>&1 &
  disown
  log "worker launched (pid $!)"
fi
