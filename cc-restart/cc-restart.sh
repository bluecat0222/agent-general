#!/usr/bin/env bash
# Restart Claude Code in tmux sessions
#
# Usage:
#   cc-restart.sh single <tmux-session> <project-dir>   — restart one session
#   cc-restart.sh all                                     — restart all running sessions
#
# Called without __RUN, it backgrounds itself with nohup and exits immediately.
# Called with __RUN=1, it performs the actual restart logic.

MAX_RETRIES=3
LOG="/tmp/cc-restart.log"
log() { echo "[$(date)] $*" >> "$LOG"; }

# Kill the claude process in a specific tmux pane.
# Handles both cases:
#   1) claude IS the pane process (started via tmux new-session ... claude)
#   2) claude is a child of a shell in the pane
kill_claude_in_pane() {
  local session="$1"
  local pane_pid
  pane_pid=$(tmux list-panes -t "$session" -F '#{pane_pid}' 2>/dev/null | head -1)
  [ -z "$pane_pid" ] && return 1

  # Check if the pane process itself is claude
  local pane_cmd
  pane_cmd=$(ps -p "$pane_pid" -o comm= 2>/dev/null)
  if [[ "$pane_cmd" == *claude* ]]; then
    log "kill_claude_in_pane: killing pane process $pane_pid (cmd=$pane_cmd)"
    kill "$pane_pid" 2>/dev/null || true
    return 0
  fi

  # Otherwise look for claude as a child process
  for pid in $(pgrep -P "$pane_pid" -f "claude" 2>/dev/null); do
    log "kill_claude_in_pane: killing child $pid"
    kill "$pid" 2>/dev/null || true
  done
  return 0
}

# Check if claude is running in a specific tmux pane
is_claude_running() {
  local session="$1"
  local pane_pid
  pane_pid=$(tmux list-panes -t "$session" -F '#{pane_pid}' 2>/dev/null | head -1)
  [ -z "$pane_pid" ] && return 1

  # Check if pane process itself is claude
  local pane_cmd
  pane_cmd=$(ps -p "$pane_pid" -o comm= 2>/dev/null)
  if [[ "$pane_cmd" == *claude* ]]; then
    return 0
  fi

  # Check children
  pgrep -P "$pane_pid" -f "claude" > /dev/null 2>&1
}

# Check if a tmux pane has claude running (for scanning)
pane_has_claude() {
  local session="$1"
  local pane_pid
  pane_pid=$(tmux list-panes -t "$session" -F '#{pane_pid}' 2>/dev/null | head -1)
  [ -z "$pane_pid" ] && return 1

  local pane_cmd
  pane_cmd=$(ps -p "$pane_pid" -o comm= 2>/dev/null)
  [[ "$pane_cmd" == *claude* ]] && return 0

  pgrep -P "$pane_pid" -f "claude" > /dev/null 2>&1
}

# Start claude in a tmux pane.
# claude runs inside a shell, so when claude exits the shell (and tmux) stays alive.
# Just send-keys to the existing shell. If session is gone, create a new one with a shell first.
start_claude_in_pane() {
  local session="$1"
  local project_dir="$2"
  local cmd="cd $project_dir && claude --dangerously-skip-permissions"

  # If session doesn't exist, create one (with default shell, not claude directly)
  if ! tmux has-session -t "$session" 2>/dev/null; then
    log "start_claude_in_pane: session $session gone, creating new session"
    tmux new-session -d -s "$session" -c "$project_dir" 2>>"$LOG"
    sleep 1
  fi

  log "start_claude_in_pane: sending command to $session: $cmd"
  tmux send-keys -t "$session" "$cmd" Enter 2>>"$LOG"
}

restart_one() {
  local session="$1"
  local project_dir="$2"

  for i in $(seq 1 "$MAX_RETRIES"); do
    log "restart_one: [$session] attempt $i/$MAX_RETRIES"
    start_claude_in_pane "$session" "$project_dir"
    sleep 15

    if is_claude_running "$session"; then
      log "restart_one: [$session] claude started successfully"
      return 0
    fi
    log "restart_one: [$session] attempt $i failed, is_claude_running returned false"
    # Log pane state for debugging
    local dbg_dead=$(tmux list-panes -t "$session" -F '#{pane_dead}' 2>/dev/null | head -1)
    local dbg_pid=$(tmux list-panes -t "$session" -F '#{pane_pid}' 2>/dev/null | head -1)
    local dbg_cmd=$(ps -p "$dbg_pid" -o comm= 2>/dev/null)
    log "restart_one: [$session] debug: pane_dead=$dbg_dead pane_pid=$dbg_pid pane_cmd=$dbg_cmd"
  done
  log "restart_one: [$session] all $MAX_RETRIES attempts failed"
  return 1
}

do_single() {
  local session="$1"
  local project_dir="$2"
  log "=== do_single: session=$session dir=$project_dir ==="
  log "do_single: waiting 10s before restart..."
  sleep 10
  restart_one "$session" "$project_dir"
  log "=== do_single: done ==="
}

do_all() {
  echo "[$(date)] Scanning for active claude sessions..."

  local -a sessions=()
  local -a dirs=()

  for session in $(tmux list-sessions -F '#{session_name}' 2>/dev/null); do
    local pane_path
    pane_path=$(tmux list-panes -t "$session" -F '#{pane_current_path}' 2>/dev/null | head -1)
    if pane_has_claude "$session"; then
      sessions+=("$session")
      dirs+=("$pane_path")
    fi
  done

  local count=${#sessions[@]}
  if [ "$count" -eq 0 ]; then
    echo "[$(date)] No active claude sessions found."
    exit 1
  fi

  echo "[$(date)] Found $count active session(s):"
  for i in $(seq 0 $((count - 1))); do
    echo "  ${sessions[$i]} -> ${dirs[$i]}"
  done

  sleep 10

  # Kill all
  for i in $(seq 0 $((count - 1))); do
    kill_claude_in_pane "${sessions[$i]}"
  done
  sleep 3

  # Restart all
  local failed=0
  for i in $(seq 0 $((count - 1))); do
    restart_one "${sessions[$i]}" "${dirs[$i]}" || ((failed++))
  done

  if [ "$failed" -gt 0 ]; then
    echo "[$(date)] $failed session(s) failed to restart."
    exit 1
  fi
  echo "[$(date)] All sessions restarted successfully."
}

# --- Entry point ---

MODE="${1:?Usage: cc-restart.sh single <session> <project-dir> | cc-restart.sh all}"

if [ "${__RUN:-}" = "1" ]; then
  case "$MODE" in
    single) do_single "$2" "$3" ;;
    all)    do_all ;;
  esac
else
  __RUN=1 nohup "$0" "$@" &>/dev/null &
fi
