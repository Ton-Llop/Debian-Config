#!/usr/bin/env bash
# Week 3 (Part B): Signals & Process Control
#
# Workload manager that spawns background CPU load using the `yes` command,
# and demonstrates signal handling + graceful shutdown.
#
# Signals handled by the manager process:
#   - SIGINT / SIGTERM : graceful shutdown (TERM workers, then KILL if needed)
#   - SIGUSR1          : print status (PIDs + resource snapshot)
#   - SIGUSR2          : toggle pause/resume (STOP/CONT workers)
#   - SIGHUP           : reload config file (change workers/nice/output)
#
# Notes:
# - Workers are spawned as a custom process name (gsx-workload-yes) so you can demo `killall`.
# - Default output is /dev/null to avoid filling the disk.
# - This script is designed to be demo-friendly rather than "always-on" production code.

set -euo pipefail
IFS=$'\n\t'

ADMIN_ROOT="${ADMIN_ROOT:-/srv/gsx-admin}"

WORKERS=4
NICE_LEVEL=10
OUTPUT="/dev/null"
GRACE_TIMEOUT=5
PAUSED=0

LOG_DIR="${ADMIN_ROOT}/logs/workload"
LOG_FILE="${LOG_DIR}/workload-manager.log"

CONFIG_FILE="${ADMIN_ROOT}/etc/gsx-admin/workload.conf"

PID_DIR="${PID_DIR:-/tmp}"
PID_FILE="${PID_FILE:-${PID_DIR}/gsx-workload-manager.pid}"

WORKER_NAME="gsx-workload-yes" # used by killall/pkill demos

WORKER_PIDS=()
STOP_REQUESTED=0

usage() {
  cat <<'EOF'
Usage:
  11-workload-signals.sh [options]

Options:
  --workers N         Number of background `yes` workers (default: 4)
  --nice N            nice level for workers (default: 10)
  --output PATH       Where workers write output (default: /dev/null)
  --timeout SECS      Graceful shutdown timeout before SIGKILL (default: 5)
  --config PATH       Config file reloaded on SIGHUP (default: /srv/gsx-admin/etc/gsx-admin/workload.conf)
  --pidfile PATH      PID file for the manager (default: /tmp/gsx-workload-manager.pid)
  --log PATH          Manager log file (default: /srv/gsx-admin/logs/workload/workload-manager.log)
  -h, --help          Show this help

How to demo signals (from another terminal):
  pid=$(cat /tmp/gsx-workload-manager.pid)
  kill -USR1 "$pid"   # status
  kill -USR2 "$pid"   # pause/resume
  kill -HUP  "$pid"   # reload config
  kill -TERM "$pid"   # graceful stop
  kill -KILL "$pid"   # force kill (no cleanup)

How to demo killall (kills only the workers):
  killall -TERM gsx-workload-yes   # graceful
  killall -KILL gsx-workload-yes   # force

Tip:
  If killall isn't available on Debian: sudo apt-get install -y psmisc
EOF
}

log() {
  # log to stdout + file (best effort)
  local msg="[$(date --iso-8601=seconds)] $*"
  echo "$msg"
  mkdir -p "$(dirname -- "$LOG_FILE")" 2>/dev/null || true
  echo "$msg" >>"$LOG_FILE" 2>/dev/null || true
}

fail() { echo "ERROR: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

write_pidfile() {
  mkdir -p "$(dirname -- "$PID_FILE")" 2>/dev/null || true
  echo "$$" >"$PID_FILE"
}

cleanup_pidfile() {
  rm -f -- "$PID_FILE" 2>/dev/null || true
}

spawn_one_worker() {
  # Use bash -c so we can set argv[0] with exec -a (nice for killall demos)
  # shellcheck disable=SC2091
  nice -n "$NICE_LEVEL" bash -c "exec -a '$WORKER_NAME' yes" >"$OUTPUT" 2>/dev/null &
  WORKER_PIDS+=("$!")
}

spawn_workers_to_target() {
  local target="$1"
  local current="${#WORKER_PIDS[@]}"
  if [ "$target" -le "$current" ]; then
    return 0
  fi
  local to_add=$((target - current))
  log "Spawning $to_add worker(s) (target=$target, nice=$NICE_LEVEL, output=$OUTPUT)"
  for _ in $(seq 1 "$to_add"); do
    spawn_one_worker
  done
}

terminate_pid_gracefully() {
  local pid="$1"
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null || true
  fi
}

terminate_pid_forcefully() {
  local pid="$1"
  if kill -0 "$pid" 2>/dev/null; then
    kill -KILL "$pid" 2>/dev/null || true
  fi
}

graceful_shutdown_workers() {
  log "Graceful shutdown: sending SIGTERM to workers..."
  local pid
  for pid in "${WORKER_PIDS[@]}"; do
    terminate_pid_gracefully "$pid"
  done

  local deadline=$((SECONDS + GRACE_TIMEOUT))
  while [ "$SECONDS" -lt "$deadline" ]; do
    local alive=0
    for pid in "${WORKER_PIDS[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        alive=1
        break
      fi
    done
    [ "$alive" -eq 0 ] && break
    sleep 0.2
  done

  # Force kill any remaining
  local still_alive=()
  for pid in "${WORKER_PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      still_alive+=("$pid")
    fi
  done

  if [ "${#still_alive[@]}" -gt 0 ]; then
    log "Timeout reached (${GRACE_TIMEOUT}s). Force-killing remaining workers: ${still_alive[*]}"
    for pid in "${still_alive[@]}"; do
      terminate_pid_forcefully "$pid"
    done
  fi
}

print_status() {
  log "=== STATUS (SIGUSR1) ==="
  log "Manager PID=$$  PGID=$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ' || echo '?')  paused=$PAUSED"
  log "Workers (${#WORKER_PIDS[@]}): ${WORKER_PIDS[*]:-<none>}"

  # Resource snapshot (best effort)
  if command -v ps >/dev/null 2>&1; then
    {
      echo "-- ps snapshot --"
      ps -o pid,ppid,pgid,pcpu,pmem,stat,comm,args -p "$$" "${WORKER_PIDS[@]:-}" 2>/dev/null || true
    } | while IFS= read -r line; do log "$line"; done
  fi

  if command -v pstree >/dev/null 2>&1; then
    {
      echo "-- pstree (manager subtree) --"
      pstree -p "$$" 2>/dev/null || true
    } | while IFS= read -r line; do log "$line"; done
  fi
}

toggle_pause() {
  if [ "$PAUSED" -eq 0 ]; then
    log "Pausing workers (SIGSTOP) (SIGUSR2)"
    local pid
    for pid in "${WORKER_PIDS[@]}"; do
      kill -STOP "$pid" 2>/dev/null || true
    done
    PAUSED=1
  else
    log "Resuming workers (SIGCONT) (SIGUSR2)"
    local pid
    for pid in "${WORKER_PIDS[@]}"; do
      kill -CONT "$pid" 2>/dev/null || true
    done
    PAUSED=0
  fi
}

reload_config() {
  # Minimal, safe-ish key=value parser (no `source`).
  log "Reload requested (SIGHUP). Reading: $CONFIG_FILE"
  if [ ! -f "$CONFIG_FILE" ]; then
    log "Config file not found; nothing to reload."
    return 0
  fi

  local new_workers="$WORKERS"
  local new_nice="$NICE_LEVEL"
  local new_output="$OUTPUT"

  while IFS='=' read -r k v; do
    k="$(echo "$k" | tr -d ' \t')"
    v="$(echo "$v" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    case "$k" in
      WORKERS)
        [[ "$v" =~ ^[0-9]+$ ]] && new_workers="$v" || true
        ;;
      NICE)
        [[ "$v" =~ ^-?[0-9]+$ ]] && new_nice="$v" || true
        ;;
      OUTPUT)
        [ -n "$v" ] && new_output="$v" || true
        ;;
    esac
  done < <(grep -E '^(WORKERS|NICE|OUTPUT)=' "$CONFIG_FILE" | tr -d '\r' || true)

  log "Config parsed: WORKERS=$new_workers NICE=$new_nice OUTPUT=$new_output"

  local restart_needed=0
  if [ "$new_nice" != "$NICE_LEVEL" ] || [ "$new_output" != "$OUTPUT" ]; then
    restart_needed=1
  fi

  WORKERS="$new_workers"
  NICE_LEVEL="$new_nice"
  OUTPUT="$new_output"

  if [ "$restart_needed" -eq 1 ]; then
    log "nice/output changed → restarting workers to apply changes"
    graceful_shutdown_workers
    WORKER_PIDS=()
    PAUSED=0
  fi

  # Scale to new worker target
  if [ "$WORKERS" -lt "${#WORKER_PIDS[@]}" ]; then
    log "Scaling down workers: current=${#WORKER_PIDS[@]} target=$WORKERS"
    # terminate extra workers from the end of the list
    while [ "${#WORKER_PIDS[@]}" -gt "$WORKERS" ]; do
      local last_index=$(( ${#WORKER_PIDS[@]} - 1 ))
      local pid_to_kill="${WORKER_PIDS[$last_index]}"
      terminate_pid_gracefully "$pid_to_kill"
      unset 'WORKER_PIDS[$last_index]'
    done
  fi
  spawn_workers_to_target "$WORKERS"

  # If paused, keep the new workers paused too
  if [ "$PAUSED" -eq 1 ]; then
    local pid
    for pid in "${WORKER_PIDS[@]}"; do
      kill -STOP "$pid" 2>/dev/null || true
    done
  fi
}

on_stop_signal() {
  # SIGINT / SIGTERM
  if [ "$STOP_REQUESTED" -eq 1 ]; then
    return 0
  fi
  STOP_REQUESTED=1
  log "Stop signal received. Starting graceful shutdown..."
  graceful_shutdown_workers
  cleanup_pidfile
  log "Shutdown complete."
  exit 0
}

on_usr1() { print_status; }
on_usr2() { toggle_pause; }
on_hup()  { reload_config; }

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --workers)
        WORKERS="${2:-}"; shift 2 ;;
      --nice)
        NICE_LEVEL="${2:-}"; shift 2 ;;
      --output)
        OUTPUT="${2:-}"; shift 2 ;;
      --timeout)
        GRACE_TIMEOUT="${2:-}"; shift 2 ;;
      --config)
        CONFIG_FILE="${2:-}"; shift 2 ;;
      --pidfile)
        PID_FILE="${2:-}"; shift 2 ;;
      --log)
        LOG_FILE="${2:-}"; shift 2 ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        fail "Unknown option: $1" ;;
    esac
  done

  [[ "$WORKERS" =~ ^[0-9]+$ ]] || fail "--workers must be an integer"
  [[ "$NICE_LEVEL" =~ ^-?[0-9]+$ ]] || fail "--nice must be an integer"
  [[ "$GRACE_TIMEOUT" =~ ^[0-9]+$ ]] || fail "--timeout must be an integer (seconds)"
}

main() {
  parse_args "$@"
  require_cmd yes
  require_cmd nice
  require_cmd ps

  mkdir -p "$LOG_DIR" 2>/dev/null || true
  mkdir -p "$(dirname -- "$CONFIG_FILE")" 2>/dev/null || true

  write_pidfile

  # Default config stub (non-fatal)
  if [ ! -f "$CONFIG_FILE" ]; then
    if ! cat >"$CONFIG_FILE" 2>/dev/null <<EOF
# gsx workload config (reloaded on SIGHUP)
# Examples:
#   WORKERS=8
#   NICE=15
#   OUTPUT=/dev/null
WORKERS=$WORKERS
NICE=$NICE_LEVEL
OUTPUT=$OUTPUT
EOF
    then
      log "Warning: couldn't write default config to $CONFIG_FILE (continuing without it)."
    fi
  fi

  log "Workload manager started. PID=$$ (pidfile: $PID_FILE)"
  log "Config file: $CONFIG_FILE (send SIGHUP to reload)"
  log "Signals: USR1=status, USR2=pause/resume, INT/TERM=graceful stop"
  log "Workers will appear as process name: $WORKER_NAME"

  # Install traps
  trap on_stop_signal INT
  trap on_stop_signal TERM
  trap on_usr1 USR1
  trap on_usr2 USR2
  trap on_hup HUP
  trap 'cleanup_pidfile' EXIT

  spawn_workers_to_target "$WORKERS"

  # Main loop (idle; signal-driven)
  while true; do
    sleep 1
  done
}

main "$@"