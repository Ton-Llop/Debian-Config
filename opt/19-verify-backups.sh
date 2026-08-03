#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

LOCK_FILE="/var/lock/gsx-week5-verify.lock"

ADMIN_ROOT="${ADMIN_ROOT:-/srv/gsx-admin}"
BACKUP_ROOT="${BACKUP_ROOT:-/srv/week5-data}"
SNAPSHOT_ROOT="${SNAPSHOT_ROOT:-${BACKUP_ROOT}/gsx-backups/snapshots}"
RESTORE_ROOT="${RESTORE_ROOT:-${BACKUP_ROOT}/gsx-backups/restore-tests}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
TARGET_LOG_DIR="${ADMIN_ROOT}/logs/backups"
TARGET_LOG="${TARGET_LOG_DIR}/week5-verify-${TS}.log"

log() { echo "[$(date -u +%FT%TZ)] $*"; }
fail() { log "ERROR: $*"; exit 1; }

latest_real_snapshot() {
  find "$SNAPSHOT_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
    | grep -E '^[0-9]{8}T[0-9]{6}Z$' \
    | sort \
    | tail -n 1
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || fail "Run as root (sudo)."
}

require_root
install -d -m 0750 -o root -g root "$TARGET_LOG_DIR"
install -d -m 0700 -o root -g root "$RESTORE_ROOT"

exec 9>"$LOCK_FILE"
flock -n 9 || fail "Verification already running"

snapshot_id="$(latest_real_snapshot || true)"
[[ -n "$snapshot_id" ]] || fail "No snapshots found in ${SNAPSHOT_ROOT}"

snapshot_dir="${SNAPSHOT_ROOT}/${snapshot_id}"
restore_dir="${RESTORE_ROOT}/${snapshot_id}-${TS}"
mkdir -p "$restore_dir"

{
  log "Latest snapshot : ${snapshot_id}"
  log "Restore target  : ${restore_dir}"

  log "Step 1/4        : verify saved manifest against snapshot contents"
  (
    cd "${snapshot_dir}/data"
    sha256sum -c "${snapshot_dir}/metadata/manifest.sha256"
  )

  log "Step 2/4        : restore snapshot to alternate location"
  rsync -aHAX "${snapshot_dir}/data/" "${restore_dir}/"

  log "Step 3/4        : verify restored files against original manifest"
  (
    cd "$restore_dir"
    sha256sum -c "${snapshot_dir}/metadata/manifest.sha256"
  )

  log "Step 4/4        : compare file inventory"
  src_list="$(mktemp)"
  restored_list="$(mktemp)"
  (
    cd "${snapshot_dir}/data"
    find . -type f | sort
  ) > "$src_list"
  (
    cd "$restore_dir"
    find . -type f | sort
  ) > "$restored_list"
  diff -u "$src_list" "$restored_list"
  rm -f "$src_list" "$restored_list"

  log "Verification OK : snapshot ${snapshot_id} restored successfully"
} | tee "$TARGET_LOG"

echo
echo "Evidence saved to: ${TARGET_LOG}"
