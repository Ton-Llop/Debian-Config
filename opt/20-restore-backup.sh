#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

BACKUP_ROOT="${BACKUP_ROOT:-/srv/week5-data}"
SNAPSHOT_ROOT="${SNAPSHOT_ROOT:-${BACKUP_ROOT}/gsx-backups/snapshots}"
SNAPSHOT_ID="${1:-latest}"
TARGET_DIR="${2:-/tmp/gsx-restore-manual}"

usage() {
  cat <<'EOF'
Usage:
  sudo bash opt/20-restore-backup.sh latest /tmp/restore-dir
  sudo bash opt/20-restore-backup.sh 20260322T021500Z /tmp/restore-dir
  sudo bash opt/20-restore-backup.sh --list
EOF
}

latest_real_snapshot() {
  find "$SNAPSHOT_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
    | grep -E '^[0-9]{8}T[0-9]{6}Z$' \
    | sort \
    | tail -n 1
}

if [[ "${1:-}" == "--list" ]]; then
  find "$SNAPSHOT_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | grep -E '^[0-9]{8}T[0-9]{6}Z$' | sort
  exit 0
fi

[[ "${EUID}" -eq 0 ]] || { echo "ERROR: Run as root (sudo)." >&2; exit 1; }

if [[ "$SNAPSHOT_ID" == "latest" ]]; then
  SNAPSHOT_ID="$(latest_real_snapshot || true)"
fi
[[ -n "$SNAPSHOT_ID" ]] || { echo "ERROR: no snapshot found" >&2; exit 1; }

SNAPSHOT_DIR="${SNAPSHOT_ROOT}/${SNAPSHOT_ID}"
[[ -d "$SNAPSHOT_DIR/data" ]] || { echo "ERROR: snapshot not found: ${SNAPSHOT_ID}" >&2; exit 1; }

install -d -m 0700 -o root -g root "$TARGET_DIR"
rsync -aHAX "${SNAPSHOT_DIR}/data/" "${TARGET_DIR}/"

echo "Restored snapshot ${SNAPSHOT_ID} into ${TARGET_DIR}"
echo "Next step: cd ${TARGET_DIR} && sha256sum -c ${SNAPSHOT_DIR}/metadata/manifest.sha256"
