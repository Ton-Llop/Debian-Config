#!/usr/bin/env bash
set -euo pipefail

LOCK_FILE="/var/lock/gsx-week1.lock"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ADMIN_ROOT="${ADMIN_ROOT:-/srv/gsx-admin}"
ADMIN_GROUP="${ADMIN_GROUP:-gsx-admin}"

RUN_NOW="${RUN_NOW:-1}"

ENV_DIR="/etc/gsx-admin"
ENV_FILE="${ENV_DIR}/backup.env"

fail() { echo "ERROR: $*" >&2; exit 1; }

effective_admin_group() {
  local grp="$ADMIN_GROUP"
  if ! getent group "$grp" >/dev/null 2>&1; then
    grp="root"
  fi
  echo "$grp"
}

install_repo_backed() {
  local rel="$1"
  local dst="$2"
  local src="$REPO_ROOT/$rel"
  local grp
  grp="$(effective_admin_group)"

  [[ -f "$src" ]] || fail "Missing repo-backed file: $src"

  install -D -m 0644 -o root -g root "$src" "$dst"
  install -D -m 0664 -o root -g "$grp" "$src" "$ADMIN_ROOT/$rel"
}

publish_script() {
  local name="$1"
  local src="$REPO_ROOT/opt/$name"
  local dst="$ADMIN_ROOT/opt/$name"
  local grp
  grp="$(effective_admin_group)"

  [[ -f "$src" ]] || fail "Missing script: $src"
  install -D -m 0750 -o root -g "$grp" "$src" "$dst"
}

escape_env_value() {
  # Escape for systemd EnvironmentFile: wrap in double-quotes, escape \ and "
  local v="$1"
  v="${v//\\/\\\\}"
  v="${v//\"/\\\"}"
  printf '%s' "\"$v\""
}

create_backup_env_if_missing() {
  # Only create if missing; never write secrets into the repo or /srv
  if [[ -f "$ENV_FILE" ]]; then
    echo "  - Found existing $ENV_FILE (keeping as-is)."
    return 0
  fi

  if [[ ! -t 0 ]]; then
    echo "  - No TTY available; cannot prompt for passphrase. Skipping $ENV_FILE creation."
    return 0
  fi

  install -d -m 0700 -o root -g root "$ENV_DIR"

  local p1="" p2=""
  while true; do
    read -r -s -p "Enter backup passphrase (leave blank for NO encryption): " p1; echo
    read -r -s -p "Confirm passphrase: " p2; echo
    [[ "$p1" == "$p2" ]] && break
    echo "Passphrases do not match. Try again."
  done

  umask 077
  if [[ -z "$p1" ]]; then
    cat >"$ENV_FILE" <<EOF
# Managed by opt/08-backup-automation.sh
ENCRYPT_MODE=none
EOF
  else
    local esc
    esc="$(escape_env_value "$p1")"
    cat >"$ENV_FILE" <<EOF
# Managed by opt/08-backup-automation.sh
ENCRYPT_MODE=gpg
PASSPHRASE=${esc}
EOF
  fi

  chown root:root "$ENV_FILE"
  chmod 0600 "$ENV_FILE"

  echo "  - Created $ENV_FILE (0600 root:root)."
}

if [[ "${EUID}" -ne 0 ]]; then
  fail "Run as root (sudo)."
fi

if [ "${GSX_PARENT_LOCK:-0}" -ne 1 ]; then
  exec 9>"$LOCK_FILE"
  flock -n 9 || { echo "Setup already running. Exiting."; exit 1; }
fi

grp="$(effective_admin_group)"

echo "[0/7] Ensure required packages..."
apt-get update -y
apt-get install -y gnupg logrotate >/dev/null

echo "[1/7] Ensure admin directories exist..."
install -d -m 2750 -o root -g "$grp" "$ADMIN_ROOT" || true
install -d -m 2750 -o root -g "$grp" "$ADMIN_ROOT"/{opt,etc,docs} || true
install -d -m 2770 -o root -g "$grp" "$ADMIN_ROOT"/{logs,backups,state} || true

echo "[2/7] Publish backup script into ${ADMIN_ROOT}/opt (runtime path used by systemd)..."
publish_script "04-backup-secrets.sh"
publish_script "09-verify-backup.sh"

echo "[3/7] Install systemd unit files (service + timer)..."
install_repo_backed "etc/systemd/system/gsx-backup.service" "/etc/systemd/system/gsx-backup.service"
install_repo_backed "etc/systemd/system/gsx-backup.timer"   "/etc/systemd/system/gsx-backup.timer"

echo "[4/7] Create root-only /etc/gsx-admin/backup.env (NOT stored in Git)..."
create_backup_env_if_missing

echo "[5/7] Reload systemd + enable timer..."
systemctl daemon-reload
systemctl enable --now gsx-backup.timer

echo "[6/7] Show timer status (next/last run)..."
systemctl list-timers --all | grep -E "gsx-backup\.timer" || true

if [[ "$RUN_NOW" == "1" ]]; then
  echo "[7/7] Run one backup now (for immediate verification)..."

  # release installer lock before starting service
  if [[ -n "${BASH_VERSION:-}" ]]; then
    flock -u 9 || true
  fi

  systemctl start gsx-backup.service
else
  echo "[7/7] Skipping immediate run (RUN_NOW=0)."
fi

echo "DONE."
echo "- Backup timer: systemctl status gsx-backup.timer"
echo "- Backup logs : journalctl -u gsx-backup.service -n 120 --no-pager"
echo "- Env file    : ${ENV_FILE} (root-only)"
echo "- Backups in  : ${ADMIN_ROOT}/backups"