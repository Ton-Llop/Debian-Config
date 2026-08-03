#!/usr/bin/env bash
set -euo pipefail

# ============================
# Week 2 (Part B): Logging & Observability
# - journald retention (persistent + size limits)
# - logrotate for /srv/gsx-admin/logs/*.log (with "su" to allow group-writable dir)
# ============================

LOCK_FILE="/var/lock/gsx-week1.lock"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ADMIN_ROOT="${ADMIN_ROOT:-/srv/gsx-admin}"
ADMIN_GROUP="${ADMIN_GROUP:-gsx-admin}"

GIT_USER="$(stat -c '%U' "$REPO_ROOT" 2>/dev/null || echo "gsx")"
GIT_GROUP="$(stat -c '%G' "$REPO_ROOT" 2>/dev/null || echo "$GIT_USER")"

fail() { echo "ERROR: $*" >&2; exit 1; }

# If gsx-admin group doesn't exist, fall back to root (prevents broken "su" / "create" directives)
effective_admin_group() {
  local grp="$ADMIN_GROUP"
  if ! getent group "$grp" >/dev/null 2>&1; then
    grp="root"
  fi
  echo "$grp"
}

ensure_repo_backed_file() {
  # Args: 1) repo-relative path under $REPO_ROOT
  local rel="$1"
  local src="${REPO_ROOT}/${rel}"
  local grp
  grp="$(effective_admin_group)"

  [[ -f "$src" ]] && return 0

  mkdir -p "$(dirname -- "$src")"

  case "$rel" in
    etc/systemd/journald.conf.d/gsx.conf)
      cat >"$src" <<'EOF'
[Journal]
Storage=persistent
SystemMaxUse=200M
SystemKeepFree=100M
RuntimeMaxUse=50M
MaxRetentionSec=1month
EOF
      ;;
    etc/logrotate.d/gsx-admin)
      # NOTE: we DO expand $grp here on purpose
      cat >"$src" <<EOF
/srv/gsx-admin/logs/*.log {
  su root ${grp}
  weekly
  rotate 8
  missingok
  notifempty
  compress
  delaycompress
  copytruncate
  create 0664 root ${grp}
}
EOF
      ;;
    *)
      fail "Missing repo-backed file: $src"
      ;;
  esac

  chown "$GIT_USER":"$GIT_GROUP" "$src" 2>/dev/null || true
  chmod 0644 "$src" 2>/dev/null || true
}

ensure_logrotate_su_directive() {
  # Ensure the gsx-admin block has `su root <group>` so logrotate doesn't skip it
  local file="$1"
  local grp
  grp="$(effective_admin_group)"

  [[ -f "$file" ]] || return 0

  # If it already has any "su root <something>" inside, leave it
  if grep -qE '^[[:space:]]*su[[:space:]]+root[[:space:]]+' "$file"; then
    return 0
  fi

  # Insert right after the opening line of the stanza
  # matches: /srv/gsx-admin/logs/*.log {
  sed -i -E "/^[[:space:]]*\/srv\/gsx-admin\/logs\/\*\.log[[:space:]]*\{[[:space:]]*$/a\\
  su root ${grp}
" "$file"
}

install_repo_backed_etc() {
  # Args:
  # 1) repo-relative path, e.g. etc/logrotate.d/gsx-admin
  # 2) /etc destination path, e.g. /etc/logrotate.d/gsx-admin
  local rel="$1"
  local dst="$2"
  local src="${REPO_ROOT}/${rel}"

  ensure_repo_backed_file "$rel"

  # If this is the logrotate config, enforce "su" even if user already had a file without it
  if [[ "$rel" == "etc/logrotate.d/gsx-admin" ]]; then
    ensure_logrotate_su_directive "$src"
  fi

  [[ -f "$src" ]] || fail "Missing repo-backed file: $src"

  install -D -m 0644 -o root -g root "$src" "$dst"

  local grp
  grp="$(effective_admin_group)"
  install -D -m 0664 -o root -g "$grp" "$src" "${ADMIN_ROOT}/${rel}"
}

if [[ "${EUID}" -ne 0 ]]; then
  fail "Run as root (sudo)."
fi

# Acquire lock only if not run under a parent lock
if [ "${GSX_PARENT_LOCK:-0}" -ne 1 ]; then
  exec 9>"$LOCK_FILE"
  flock -n 9 || { echo "Setup already running. Exiting."; exit 1; }
fi

echo "[1/7] Install observability tooling (logrotate)..."
apt-get update -y
apt-get install -y logrotate

echo "[2/7] Configure journald retention (persistent + size limits)..."
install -d -m 2755 -o root -g systemd-journal /var/log/journal || true
install_repo_backed_etc "etc/systemd/journald.conf.d/gsx.conf" "/etc/systemd/journald.conf.d/gsx.conf"
systemctl restart systemd-journald

echo "[3/7] Configure log rotation for admin log files..."
grp="$(effective_admin_group)"
install -d -m 2770 -o root -g "$grp" "${ADMIN_ROOT}/logs" || true
install_repo_backed_etc "etc/logrotate.d/gsx-admin" "/etc/logrotate.d/gsx-admin"

echo "[4/7] Repo-backed configs installed into /etc and mirrored into /srv/gsx-admin/etc."

echo "[5/7] Basic validation (non-destructive)..."
logrotate -d /etc/logrotate.conf >/dev/null || true
journalctl --disk-usage || true

echo "[6/7] Git sync (best-effort)..."
if [[ -d "$REPO_ROOT/.git" ]]; then
  sudo -u "$GIT_USER" git -C "$REPO_ROOT" add \
    "etc/systemd/journald.conf.d/gsx.conf" \
    "etc/logrotate.d/gsx-admin" || true

  if ! sudo -u "$GIT_USER" git -C "$REPO_ROOT" diff --cached --quiet; then
    sudo -u "$GIT_USER" git -C "$REPO_ROOT" commit -m "Week2 (Part B): journald retention + logrotate (su fix)" || \
      echo "WARNING: git commit failed (set user.name/user.email). Commit later."

    sudo -u "$GIT_USER" git -C "$REPO_ROOT" push origin main 2>/dev/null || \
      sudo -u "$GIT_USER" git -C "$REPO_ROOT" push origin master 2>/dev/null || \
      echo "WARNING: push failed (auth/branch). This is OK — push later."
  else
    echo "  - No changes to commit."
  fi
else
  echo "NOTE: no .git found at $REPO_ROOT; skipping commit/push."
fi

echo "[7/7] Done. Next: run opt/07-verify-logging.sh for evidence output."
