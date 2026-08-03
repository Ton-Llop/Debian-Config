#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-}"
if [[ -z "$REPO_DIR" ]]; then
  if [[ -d "${SCRIPT_DIR}/../.git" ]]; then
    REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
  elif [[ -d "/home/gsx/gsx-admin/.git" ]]; then
    REPO_DIR="/home/gsx/gsx-admin"
  else
    REPO_DIR="$(pwd)"
  fi
fi

REPO_OWNER="$(stat -c '%U' "$REPO_DIR" 2>/dev/null || echo 'gsx')"
GSX_REPO_ROOT="$REPO_DIR"
GSX_REPO_OWNER="$REPO_OWNER"
ADMIN_ROOT="${ADMIN_ROOT:-/srv/gsx-admin}"
BACKUP_ROOT="${BACKUP_ROOT:-/srv/week5-data}"
RUN_VERIFY=1
SKIP_WEEK5=0
RUN_WEEK2_BACKUP_NOW="${RUN_WEEK2_BACKUP_NOW:-1}"
RUN_WEEK5_NOW="${RUN_WEEK5_NOW:-1}"
RUN_WEEK5_VERIFY_NOW="${RUN_WEEK5_VERIFY_NOW:-1}"
WEEK2_ENCRYPT_MODE="${WEEK2_ENCRYPT_MODE:-${ENCRYPT_MODE:-}}"
WEEK2_PASSPHRASE="${WEEK2_PASSPHRASE:-${PASSPHRASE:-}}"
WEEK2_ENV_FILE="/etc/gsx-admin/backup.env"
WEEK5_ENV_CREATED="/etc/gsx-admin/backup-tot.env"
WEEK5_ENV_USED_BY_UNITS="/etc/gsx-admin/backup-week5.env"

usage() {
  cat <<EOF2
Usage:
  sudo bash opt/00-bootstrap-server.sh [options]

Options:
  --setup-only        Run provisioning only; skip verification scripts.
  --skip-week5        Skip Week 5 dedicated-disk backup setup.
  --repo-dir DIR      Use DIR as the repo root.
  --help              Show this help.

Useful environment variables:
  ADMIN_ROOT=/srv/gsx-admin
  BACKUP_ROOT=/srv/week5-data
  RUN_WEEK2_BACKUP_NOW=0
  RUN_WEEK5_NOW=0
  RUN_WEEK5_VERIFY_NOW=0
  WEEK2_ENCRYPT_MODE=none|gpg
  WEEK2_PASSPHRASE='your-passphrase'

Examples:
  sudo bash opt/00-bootstrap-server.sh
  sudo BACKUP_ROOT=/mnt/backup-disk bash opt/00-bootstrap-server.sh
  sudo WEEK2_ENCRYPT_MODE=none RUN_WEEK5_NOW=0 bash opt/00-bootstrap-server.sh --setup-only
EOF2
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

note() {
  echo "--> $*"
}

run_step() {
  local title="$1"
  shift
  echo
  echo "================================================================"
  echo "$title"
  echo "================================================================"
  "$@"
}

escape_env_value() {
  local v="$1"
  v="${v//\\/\\\\}"
  v="${v//\"/\\\"}"
  printf '%s' "$v"
}

prepare_week2_backup_env() {
  install -d -m 0700 -o root -g root /etc/gsx-admin

  if [[ -f "$WEEK2_ENV_FILE" ]]; then
    note "Keeping existing ${WEEK2_ENV_FILE}"
    return 0
  fi

  if [[ -n "$WEEK2_PASSPHRASE" && -z "$WEEK2_ENCRYPT_MODE" ]]; then
    WEEK2_ENCRYPT_MODE="gpg"
  fi

  if [[ -z "$WEEK2_ENCRYPT_MODE" ]]; then
    note "No Week 2 backup env requested; 08-backup-automation.sh will prompt on a TTY or fall back to plaintext backups."
    return 0
  fi

  case "$WEEK2_ENCRYPT_MODE" in
    none)
      cat > "$WEEK2_ENV_FILE" <<EOF2
# Managed by opt/00-bootstrap-server.sh
ENCRYPT_MODE=none
EOF2
      ;;
    gpg)
      [[ -n "$WEEK2_PASSPHRASE" ]] || fail "WEEK2_ENCRYPT_MODE=gpg requires WEEK2_PASSPHRASE"
      local escaped
      escaped="$(escape_env_value "$WEEK2_PASSPHRASE")"
      cat > "$WEEK2_ENV_FILE" <<EOF2
# Managed by opt/00-bootstrap-server.sh
ENCRYPT_MODE=gpg
PASSPHRASE="${escaped}"
EOF2
      ;;
    auto)
      cat > "$WEEK2_ENV_FILE" <<EOF2
# Managed by opt/00-bootstrap-server.sh
ENCRYPT_MODE=auto
EOF2
      ;;
    *)
      fail "Invalid WEEK2_ENCRYPT_MODE=${WEEK2_ENCRYPT_MODE}. Use auto, gpg or none."
      ;;
  esac

  chown root:root "$WEEK2_ENV_FILE"
  chmod 0600 "$WEEK2_ENV_FILE"
  note "Created ${WEEK2_ENV_FILE}"
}

verify_week1_core() {
  echo "== Week 1 verification =="

  systemctl is-enabled ssh >/dev/null 2>&1 || systemctl is-enabled sshd >/dev/null 2>&1 || fail "SSH service is not enabled"
  systemctl is-active ssh >/dev/null 2>&1 || systemctl is-active sshd >/dev/null 2>&1 || fail "SSH service is not active"

  local ssh_cfg="/etc/ssh/sshd_config.d/gsx-hardening.conf"
  [[ -f "$ssh_cfg" ]] || fail "Missing ${ssh_cfg}"

  local port
  port="$(awk '$1=="Port"{print $2}' "$ssh_cfg" | tail -n1)"
  port="${port:-22}"
  ss -tlnp | grep -q ":${port} " || fail "sshd is not listening on port ${port}"

  [[ -f "/etc/sudoers.d/gsx-admin" ]] || fail "Missing /etc/sudoers.d/gsx-admin"
  if command -v visudo >/dev/null 2>&1; then
    visudo -cf /etc/sudoers.d/gsx-admin >/dev/null || fail "Invalid sudoers drop-in for gsx-admin"
  fi

  getent group gsx-admin >/dev/null 2>&1 || fail "Missing gsx-admin group"
  [[ -d "$ADMIN_ROOT" ]] || fail "Missing ${ADMIN_ROOT}"

  echo "OK: Week 1 core looks correct."
}

ensure_week5_env_compat() {
  if [[ -f "$WEEK5_ENV_CREATED" && ! -e "$WEEK5_ENV_USED_BY_UNITS" ]]; then
    ln -s "$WEEK5_ENV_CREATED" "$WEEK5_ENV_USED_BY_UNITS"
    note "Created compatibility symlink ${WEEK5_ENV_USED_BY_UNITS} -> ${WEEK5_ENV_CREATED}"
    return 0
  fi

  if [[ -e "$WEEK5_ENV_CREATED" && -e "$WEEK5_ENV_USED_BY_UNITS" ]]; then
    if [[ "$(readlink -f "$WEEK5_ENV_CREATED")" != "$(readlink -f "$WEEK5_ENV_USED_BY_UNITS")" ]]; then
      note "Week 5 env name mismatch detected: both ${WEEK5_ENV_CREATED} and ${WEEK5_ENV_USED_BY_UNITS} exist. Review and keep only one canonical file."
    fi
  fi
}

require_repo_file() {
  local rel="$1"
  [[ -f "${REPO_DIR}/${rel}" ]] || fail "Missing required repo file: ${REPO_DIR}/${rel}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --setup-only)
      RUN_VERIFY=0
      ;;
    --skip-week5)
      SKIP_WEEK5=1
      ;;
    --repo-dir)
      shift
      [[ $# -gt 0 ]] || fail "--repo-dir requires a value"
      REPO_DIR="$1"
      GSX_REPO_ROOT="$REPO_DIR"
      REPO_OWNER="$(stat -c '%U' "$REPO_DIR" 2>/dev/null || echo 'gsx')"
      GSX_REPO_OWNER="$REPO_OWNER"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
  shift
done

[[ "${EUID}" -eq 0 ]] || fail "Run as root (sudo)."
[[ -d "$REPO_DIR" ]] || fail "Repo dir not found: ${REPO_DIR}"
[[ -d "${REPO_DIR}/.git" ]] || note "${REPO_DIR} is not a git checkout. The script can still run, but repo-backed mirroring may be less useful."

require_repo_file "opt/01-install-packages.sh"
require_repo_file "opt/02-setup-admin-dirs.sh"
require_repo_file "opt/05-nginx_setup.sh"
require_repo_file "opt/06-logging-observability-setup.sh"
require_repo_file "opt/07-verify-logging.sh"
require_repo_file "opt/08-backup-automation.sh"
require_repo_file "opt/09-verify-backup.sh"
require_repo_file "opt/12-resource-limits-setup.sh"
require_repo_file "opt/13-verify-resource-limits.sh"
require_repo_file "opt/15-week4-users-groups-setup.sh"
require_repo_file "opt/16-verify-week4-security.sh"
require_repo_file "opt/17-backup-setup.sh"
require_repo_file "opt/19-verify-backups.sh"

note "Repo root: ${REPO_DIR}"
note "Admin root: ${ADMIN_ROOT}"
if [[ "$SKIP_WEEK5" -eq 0 ]]; then
  note "Week 5 backup root: ${BACKUP_ROOT}"
fi

prepare_week2_backup_env

run_step "[1/10] Week 1 - base packages and hardening" \
  env GSX_REPO_ROOT="$GSX_REPO_ROOT" GSX_REPO_OWNER="$GSX_REPO_OWNER" bash "$REPO_DIR/opt/01-install-packages.sh"

run_step "[2/10] Week 1 - admin directories and sudo policy" \
  bash "$REPO_DIR/opt/02-setup-admin-dirs.sh"

run_step "[3/10] Week 2 - nginx, custom service and timer" \
  bash "$REPO_DIR/opt/05-nginx_setup.sh" "$REPO_DIR"

run_step "[4/10] Week 2 - logging and observability" \
  bash "$REPO_DIR/opt/06-logging-observability-setup.sh"

run_step "[5/10] Week 2 - backup automation" \
  env RUN_NOW="$RUN_WEEK2_BACKUP_NOW" bash "$REPO_DIR/opt/08-backup-automation.sh"

run_step "[6/10] Week 3 - resource limits and workload service" \
  bash "$REPO_DIR/opt/12-resource-limits-setup.sh" "$REPO_DIR"

run_step "[7/10] Week 4 - users, groups, ACLs and login environment" \
  bash "$REPO_DIR/opt/15-week4-users-groups-setup.sh" "$REPO_DIR"

if [[ "$SKIP_WEEK5" -eq 0 ]]; then
  findmnt -n -o SOURCE -T "$BACKUP_ROOT" >/dev/null 2>&1 || \
    fail "BACKUP_ROOT=${BACKUP_ROOT} is not mounted. Mount the Week 5 backup disk first or rerun with --skip-week5."

  run_step "[8/10] Week 5 - dedicated-disk backup setup" \
    env BACKUP_ROOT="$BACKUP_ROOT" RUN_NOW="$RUN_WEEK5_NOW" RUN_VERIFY_NOW="$RUN_WEEK5_VERIFY_NOW" bash "$REPO_DIR/opt/17-backup-setup.sh" "$REPO_DIR"

  ensure_week5_env_compat
else
  echo
  echo "================================================================"
  echo "[8/10] Week 5 skipped"
  echo "================================================================"
fi

if [[ "$RUN_VERIFY" -eq 1 ]]; then
  run_step "[9/10] Verification - Week 1 core" verify_week1_core

  run_step "[10/10] Verification - Weeks 2 to 5" bash -lc '
    set -euo pipefail
    REPO_DIR="$1"
    SKIP_WEEK5="$2"
    bash "$REPO_DIR/opt/07-verify-logging.sh"
    bash "$REPO_DIR/opt/09-verify-backup.sh"
    bash "$REPO_DIR/opt/13-verify-resource-limits.sh"
    bash "$REPO_DIR/opt/16-verify-week4-security.sh"
    if [[ "$SKIP_WEEK5" -eq 0 ]]; then
      bash "$REPO_DIR/opt/19-verify-backups.sh"
    fi
  ' _ "$REPO_DIR" "$SKIP_WEEK5"
else
  note "Verification phase skipped (--setup-only)."
fi

echo
echo "Bootstrap completed successfully."
echo "- Run again any time: sudo bash opt/00-bootstrap-server.sh"
echo "- Setup only         : sudo bash opt/00-bootstrap-server.sh --setup-only"
if [[ "$SKIP_WEEK5" -eq 0 ]]; then
  echo "- Week 5 logs        : journalctl -u gsx-backup-tot.service -n 100 --no-pager"
fi
