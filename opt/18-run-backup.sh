#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

LOCK_FILE="/var/lock/gsx-week5-backup.lock"

ADMIN_ROOT="${ADMIN_ROOT:-/srv/gsx-admin}"
ADMIN_GROUP="${ADMIN_GROUP:-gsx-admin}"
BACKUP_ROOT="${BACKUP_ROOT:-/srv/week5-data}"
SNAPSHOT_ROOT="${SNAPSHOT_ROOT:-${BACKUP_ROOT}/gsx-backups/snapshots}"
RESTORE_ROOT="${RESTORE_ROOT:-${BACKUP_ROOT}/gsx-backups/restore-tests}"
OFFSITE_DIR="${OFFSITE_DIR:-}"
KEEP_DAILY_DAYS="${KEEP_DAILY_DAYS:-7}"
KEEP_WEEKLY_WEEKS="${KEEP_WEEKLY_WEEKS:-4}"
KEEP_MONTHLY_MONTHS="${KEEP_MONTHLY_MONTHS:-3}"
REQUIRE_SEPARATE_FILESYSTEM="${REQUIRE_SEPARATE_FILESYSTEM:-1}"
BACKUP_SOURCES_DEFAULT="/etc /home/gsx /home/greendevcorp /home/dev1 /home/dev2 /home/dev3 /home/dev4 /srv/gsx-admin /var/www"
BACKUP_SOURCES="${BACKUP_SOURCES:-$BACKUP_SOURCES_DEFAULT}"
LOG_DIR="${ADMIN_ROOT}/logs/backups"
STATE_DIR="${ADMIN_ROOT}/state/week5-backup"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
SNAPSHOT_TMP="${SNAPSHOT_ROOT}/.tmp-${TS}"
SNAPSHOT_FINAL="${SNAPSHOT_ROOT}/${TS}"
LATEST_LINK="${SNAPSHOT_ROOT}/latest"
HOST_FQDN="$(hostname -f 2>/dev/null || hostname)"

log() { echo "[$(date -u +%FT%TZ)] $*"; }
fail() { log "ERROR: $*"; exit 1; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    fail "Run as root (sudo)."
  fi
}

safe_admin_group() {
  if getent group "$ADMIN_GROUP" >/dev/null 2>&1; then
    echo "$ADMIN_GROUP"
  else
    echo "root"
  fi
}

ensure_layout() {
  local grp
  grp="$(safe_admin_group)"
  install -d -m 2770 -o root -g "$grp" "${ADMIN_ROOT}/logs" "${ADMIN_ROOT}/logs/backups" || true
  install -d -m 2770 -o root -g "$grp" "${ADMIN_ROOT}/state" || true
  install -d -m 0750 -o root -g root "$STATE_DIR"
  install -d -m 0750 -o root -g root "$BACKUP_ROOT"
  install -d -m 0700 -o root -g root "$SNAPSHOT_ROOT"
  install -d -m 0700 -o root -g root "$RESTORE_ROOT"
}

check_backup_target() {
  local root_fs backup_fs
  root_fs="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
  backup_fs="$(findmnt -n -o SOURCE -T "$BACKUP_ROOT" 2>/dev/null || true)"
  [[ -n "$backup_fs" ]] || fail "Backup root $BACKUP_ROOT is not on a mounted filesystem"
  if [[ "$REQUIRE_SEPARATE_FILESYSTEM" == "1" && "$root_fs" == "$backup_fs" ]]; then
    fail "Backup root $BACKUP_ROOT is on the same filesystem as /. This does not meet the Week 5 design goal."
  fi
}

latest_real_snapshot() {
  find "$SNAPSHOT_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
    | grep -E '^[0-9]{8}T[0-9]{6}Z$' \
    | sort \
    | tail -n 1
}

sync_one_source() {
  local src="$1"
  local -a rsync_opts
  rsync_opts=(
    -aHAX --numeric-ids --delete --delete-excluded --relative
    --exclude '.cache/'
    --exclude '.local/share/Trash/'
    --exclude 'lost+found/'
  )

  if [[ -n "${PREVIOUS_SNAPSHOT:-}" && -d "${PREVIOUS_SNAPSHOT}/data" ]]; then
    rsync_opts+=(--link-dest="${PREVIOUS_SNAPSHOT}/data")
  fi

  if [[ -d "$src" ]]; then
    rsync "${rsync_opts[@]}" "${src%/}/" "${SNAPSHOT_TMP}/data/"
  else
    rsync "${rsync_opts[@]}" "$src" "${SNAPSHOT_TMP}/data/"
  fi
}

write_metadata() {
  local backup_fs root_fs source_count
  backup_fs="$(findmnt -n -o SOURCE -T "$BACKUP_ROOT" 2>/dev/null || echo unknown)"
  root_fs="$(findmnt -n -o SOURCE / 2>/dev/null || echo unknown)"
  source_count="${#SOURCE_PATHS[@]}"

  cat > "${SNAPSHOT_TMP}/metadata/backup-info.txt" <<EOF
snapshot_id=${TS}
hostname=${HOST_FQDN}
created_utc=$(date -u +%FT%TZ)
root_filesystem=${root_fs}
backup_filesystem=${backup_fs}
backup_root=${BACKUP_ROOT}
snapshot_root=${SNAPSHOT_ROOT}
restore_root=${RESTORE_ROOT}
previous_snapshot=$(basename "${PREVIOUS_SNAPSHOT:-none}")
source_count=${source_count}
backup_sources=${BACKUP_SOURCES}
retention_daily_days=${KEEP_DAILY_DAYS}
retention_weekly_weeks=${KEEP_WEEKLY_WEEKS}
retention_monthly_months=${KEEP_MONTHLY_MONTHS}
offsite_dir=${OFFSITE_DIR:-disabled}
EOF

  du -sh "${SNAPSHOT_TMP}/data" > "${SNAPSHOT_TMP}/metadata/size.txt"
  df -h "$BACKUP_ROOT" > "${SNAPSHOT_TMP}/metadata/filesystem.txt"

  (
    cd "${SNAPSHOT_TMP}/data"
    find . -type f -print0 | sort -z | tr '\0' '\n' > "${SNAPSHOT_TMP}/metadata/files.txt"
    while IFS= read -r rel; do
      [[ -n "$rel" ]] || continue
      sha256sum "$rel"
    done < "${SNAPSHOT_TMP}/metadata/files.txt" > "${SNAPSHOT_TMP}/metadata/manifest.sha256"
  )
}

should_keep_snapshot() {
  local id="$1"
  local latest="$2"
  local yyyy mm dd hh mi ss snap_epoch now_epoch age_days dow

  [[ "$id" == "$latest" ]] && return 0

  yyyy="${id:0:4}"
  mm="${id:4:2}"
  dd="${id:6:2}"
  hh="${id:9:2}"
  mi="${id:11:2}"
  ss="${id:13:2}"

  snap_epoch="$(date -u -d "${yyyy}-${mm}-${dd} ${hh}:${mi}:${ss}" +%s)"
  now_epoch="$(date -u +%s)"
  age_days=$(( (now_epoch - snap_epoch) / 86400 ))
  dow="$(date -u -d "${yyyy}-${mm}-${dd}" +%u)"

  if (( age_days <= KEEP_DAILY_DAYS )); then
    return 0
  fi
  if (( age_days <= KEEP_WEEKLY_WEEKS * 7 )) && [[ "$dow" == "7" ]]; then
    return 0
  fi
  if (( age_days <= KEEP_MONTHLY_MONTHS * 31 )) && [[ "$dd" == "01" ]]; then
    return 0
  fi
  return 1
}

prune_old_snapshots() {
  local latest
  latest="$(latest_real_snapshot)"
  [[ -n "$latest" ]] || return 0

  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    if should_keep_snapshot "$id" "$latest"; then
      log "Retention keep  : $id"
    else
      log "Retention prune : $id"
      rm -rf --one-file-system "${SNAPSHOT_ROOT}/${id}"
    fi
  done < <(find "$SNAPSHOT_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | grep -E '^[0-9]{8}T[0-9]{6}Z$' | sort)
}

offsite_sync_latest() {
  [[ -n "$OFFSITE_DIR" ]] || { log "Offsite sync    : disabled"; return 0; }
  install -d -m 0700 -o root -g root "$OFFSITE_DIR"
  log "Offsite sync    : ${OFFSITE_DIR}"
  rsync -aHAX --delete "${SNAPSHOT_FINAL}/" "${OFFSITE_DIR}/latest/"
}

require_root
ensure_layout
check_backup_target

exec 9>"$LOCK_FILE"
flock -n 9 || fail "Backup already running"

install -d -m 0700 -o root -g root "${SNAPSHOT_TMP}/data" "${SNAPSHOT_TMP}/metadata"

IFS=' ' read -r -a SOURCE_PATHS <<< "$BACKUP_SOURCES"
[[ "${#SOURCE_PATHS[@]}" -gt 0 ]] || fail "No backup sources configured"

prev_id="$(latest_real_snapshot || true)"
PREVIOUS_SNAPSHOT=""
if [[ -n "$prev_id" && -d "${SNAPSHOT_ROOT}/${prev_id}/data" ]]; then
  PREVIOUS_SNAPSHOT="${SNAPSHOT_ROOT}/${prev_id}"
fi

log "Snapshot root   : ${SNAPSHOT_ROOT}"
log "Current snapshot: ${TS}"
log "Previous        : ${prev_id:-none}"
log "Sources         : ${BACKUP_SOURCES}"

copied_count=0
skipped_count=0
for src in "${SOURCE_PATHS[@]}"; do
  [[ -n "$src" ]] || continue
  case "$src" in
    "$BACKUP_ROOT"|"$SNAPSHOT_ROOT"|"$RESTORE_ROOT")
      log "SKIP source     : ${src} (recursive)"
      skipped_count=$((skipped_count + 1))
      continue
      ;;
  esac
  if [[ ! -e "$src" ]]; then
    log "SKIP source     : ${src} (missing)"
    skipped_count=$((skipped_count + 1))
    continue
  fi
  log "Sync source     : ${src}"
  sync_one_source "$src"
  copied_count=$((copied_count + 1))
done

(( copied_count > 0 )) || fail "All configured sources were skipped"

write_metadata
mv "$SNAPSHOT_TMP" "$SNAPSHOT_FINAL"
ln -sfn "$TS" "$LATEST_LINK"

prune_old_snapshots
offsite_sync_latest

log "Completed       : ${SNAPSHOT_FINAL}"
log "Source summary  : copied=${copied_count} skipped=${skipped_count}"
