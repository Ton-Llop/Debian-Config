#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

LOCK_FILE="/var/lock/gsx-week5-setup.lock"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${1:-}"
if [[ -z "$REPO_DIR" ]]; then
  if [[ -d "${SCRIPT_DIR}/../.git" ]]; then
    REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
  elif [[ -d "/home/gsx/gsx-admin/.git" ]]; then
    REPO_DIR="/home/gsx/gsx-admin"
  else
    REPO_DIR="$(pwd)"
  fi
fi

REPO_OWNER="$(stat -c '%U' "$REPO_DIR" 2>/dev/null || echo "gsx")"
ADMIN_ROOT="${ADMIN_ROOT:-/srv/gsx-admin}"
ADMIN_GROUP="${ADMIN_GROUP:-gsx-admin}"
BACKUP_ROOT="${BACKUP_ROOT:-/srv/week5-data}"
BACKUP_ENV="/etc/gsx-admin/backup-tot.env"
RUN_NOW="${RUN_NOW:-1}"
RUN_VERIFY_NOW="${RUN_VERIFY_NOW:-1}"

fail() { echo "ERROR: $*" >&2; exit 1; }

mirror_repo_file() {
  local rel="$1"
  local src="${REPO_DIR}/${rel}"
  local dst="/${rel}"

  [[ -f "$src" ]] || fail "Missing repo file: $src"

  install -D -m 0644 -o root -g root "$src" "$dst"

  local grp="$ADMIN_GROUP"
  if ! getent group "$grp" >/dev/null 2>&1; then
    grp="root"
  fi
  install -D -m 0664 -o root -g "$grp" "$src" "${ADMIN_ROOT}/${rel}"
}

publish_script() {
  local name="$1"
  local src="${REPO_DIR}/opt/${name}"
  [[ -f "$src" ]] || fail "Missing script: $src"

  local grp="$ADMIN_GROUP"
  if ! getent group "$grp" >/dev/null 2>&1; then
    grp="root"
  fi
  install -D -m 0750 -o root -g "$grp" "$src" "${ADMIN_ROOT}/opt/${name}"
}

create_backup_env_if_missing() {
  local example="${REPO_DIR}/etc/gsx-admin/backup-tot.env.example"
  [[ -f "$example" ]] || fail "Missing example env file: $example"

  install -d -m 0750 -o root -g root /etc/gsx-admin
  if [[ -f "$BACKUP_ENV" ]]; then
    echo "  - Keeping existing ${BACKUP_ENV}"
    return 0
  fi

  install -m 0640 -o root -g root "$example" "$BACKUP_ENV"
  echo "  - Created ${BACKUP_ENV} from example"
}

if [[ "${EUID}" -ne 0 ]]; then
  fail "Run as root (sudo)."
fi

[[ -d "$REPO_DIR" ]] || fail "Repo dir not found: $REPO_DIR"

exec 9>"$LOCK_FILE"
flock -n 9 || { echo "Week 5 backup setup already running. Exiting."; exit 1; }

export DEBIAN_FRONTEND=noninteractive

echo "[1/8] Install required packages..."
apt-get update -y
apt-get install -y rsync coreutils findutils >/dev/null

echo "[2/8] Validate backup target mount..."
install -d -m 0750 -o root -g root "$BACKUP_ROOT"
root_fs="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
backup_fs="$(findmnt -n -o SOURCE -T "$BACKUP_ROOT" 2>/dev/null || true)"
if [[ -z "$backup_fs" ]]; then
  fail "${BACKUP_ROOT} is not mounted. Mount the Week 5 disk first."
fi
if [[ "$root_fs" == "$backup_fs" ]]; then
  fail "${BACKUP_ROOT} resolves to the same filesystem as /. Refusing to place backups on the root disk."
fi

echo "[3/8] Create backup directory layout on the dedicated disk..."
install -d -m 0750 -o root -g root "$BACKUP_ROOT/gsx-backups"
install -d -m 0700 -o root -g root "$BACKUP_ROOT/gsx-backups/snapshots"
install -d -m 0700 -o root -g root "$BACKUP_ROOT/gsx-backups/restore-tests"

echo "[4/8] Install Week 5 runtime configuration..."
create_backup_env_if_missing

if ! grep -Eq '^BACKUP_ROOT=' "$BACKUP_ENV"; then
  printf '\nBACKUP_ROOT=%q\n' "$BACKUP_ROOT" >> "$BACKUP_ENV"
fi
if ! grep -Eq '^SNAPSHOT_ROOT=' "$BACKUP_ENV"; then
  printf 'SNAPSHOT_ROOT=%q\n' "$BACKUP_ROOT/gsx-backups/snapshots" >> "$BACKUP_ENV"
fi
if ! grep -Eq '^RESTORE_ROOT=' "$BACKUP_ENV"; then
  printf 'RESTORE_ROOT=%q\n' "$BACKUP_ROOT/gsx-backups/restore-tests" >> "$BACKUP_ENV"
fi
chmod 0640 "$BACKUP_ENV"
chown root:root "$BACKUP_ENV"

echo "[5/8] Publish Week 5 scripts to ${ADMIN_ROOT}/opt..."
publish_script "17-backup-setup.sh"
publish_script "18-run-backup.sh"
publish_script "19-verify-backups.sh"
publish_script "20-restore-backup.sh"

echo "[6/8] Install systemd units into /etc/systemd/system and mirror them into ${ADMIN_ROOT}..."
mirror_repo_file "etc/systemd/system/gsx-backup-tot.service"
mirror_repo_file "etc/systemd/system/gsx-backup-tot.timer"
mirror_repo_file "etc/systemd/system/gsx-backup-tot-verify.service"
mirror_repo_file "etc/systemd/system/gsx-backup-tot-verify.timer"

echo "[7/8] Reload systemd and enable timers..."
systemctl daemon-reload
systemctl enable --now gsx-backup-tot.timer
systemctl enable --now gsx-backup-tot-verify.timer

echo "[8/8] Optional first execution for evidence/demo..."
if [[ "$RUN_NOW" == "1" ]]; then
  systemctl start gsx-backup-tot.service
else
  echo "  - Skipping initial backup run (RUN_NOW=0)."
fi
if [[ "$RUN_VERIFY_NOW" == "1" ]]; then
  systemctl start gsx-backup-tot-verify.service || true
else
  echo "  - Skipping initial verification run (RUN_VERIFY_NOW=0)."
fi

echo
echo "DONE."
echo "- Backup disk    : $(findmnt -n -o TARGET,SOURCE -T "$BACKUP_ROOT" | xargs echo)"
echo "- Env file       : ${BACKUP_ENV}"
echo "- Backup timer   : systemctl status gsx-backup-tot.timer"
echo "- Verify timer   : systemctl status gsx-backup-tot-verify.timer"
echo "- Backup logs    : journalctl -u gsx-backup-tot.service -n 100 --no-pager"
echo "- Verify logs    : journalctl -u gsx-backup-tot-verify.service -n 100 --no-pager"
