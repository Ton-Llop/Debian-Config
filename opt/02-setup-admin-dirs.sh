#!/usr/bin/env bash
set -euo pipefail

# =========================
# Config (override via env)
# =========================
ADMIN_GROUP="${ADMIN_GROUP:-gsx-admin}"
FIRST_ADMIN="${FIRST_ADMIN:-gsx}"

# Recommended: /srv for shared server-managed workspace (override if you prefer /opt)
ADMIN_ROOT="${ADMIN_ROOT:-/srv/gsx-admin}"

SUDOERS_DIR="/etc/sudoers.d"
SUDOERS_FILE="${SUDOERS_DIR}/${ADMIN_GROUP}"

LOCK_FILE="/var/lock/gsx-week1.lock"

# Any extra usernames passed as args will also be added to the group
EXTRA_ADMINS=("$@")

# Repo root detection (script expected in repo/opt/)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# =========================
# Must be run as root
# =========================
if [ "${EUID}" -ne 0 ]; then
  echo "ERROR: Run as root (initial setup)."
  exit 1
fi

# =========================
# Global lock
# =========================
# Lock only when run standalone (03-verify.sh will set GSX_PARENT_LOCK=1)
if [ "${GSX_PARENT_LOCK:-0}" -ne 1 ]; then
  exec 9>"$LOCK_FILE"
  flock -n 9 || { echo "Setup already running. Exiting."; exit 1; }
fi

echo "[1/5] Create ${ADMIN_GROUP} and add ${FIRST_ADMIN}"

groupadd -f "$ADMIN_GROUP"

if id "$FIRST_ADMIN" >/dev/null 2>&1; then
  usermod -aG "$ADMIN_GROUP" "$FIRST_ADMIN"
else
  echo "WARNING: user '${FIRST_ADMIN}' does not exist yet; cannot add to group."
fi

for u in "${EXTRA_ADMINS[@]}"; do
  [ "$u" = "$FIRST_ADMIN" ] && continue
  if id "$u" >/dev/null 2>&1; then
    usermod -aG "$ADMIN_GROUP" "$u"
  else
    echo "WARNING: user '${u}' does not exist; skipping."
  fi
done

echo "[2/5] Grant sudo to %${ADMIN_GROUP} (sudoers drop-in)"

install -d -m 0755 -o root -g root "$SUDOERS_DIR"

TMP="$(mktemp)"
cat > "$TMP" <<EOF
# Allow members of ${ADMIN_GROUP} to run sudo
%${ADMIN_GROUP} ALL=(ALL:ALL) ALL
EOF

# Validate if visudo exists (safe); otherwise still install and warn.
if command -v visudo >/dev/null 2>&1; then
  visudo -cf "$TMP" >/dev/null
else
  echo "WARNING: visudo not found; cannot validate sudoers syntax now."
fi

install -m 0440 -o root -g root "$TMP" "$SUDOERS_FILE"
rm -f "$TMP"

echo "[3/5] Create admin filesystem at ${ADMIN_ROOT} (group-private)"

# Root dir: only root + gsx-admin can traverse; others have no access
install -d -m 2750 -o root -g "$ADMIN_GROUP" "$ADMIN_ROOT"
chmod g+s "$ADMIN_ROOT"

# Subdirs:
# - opt/etc/docs are readable/executable for group, not writable (reduce accidents)
# - logs/state/backups are group-writable
install -d -m 2750 -o root -g "$ADMIN_GROUP" "$ADMIN_ROOT"/{opt,etc,docs}
install -d -m 2770 -o root -g "$ADMIN_GROUP" "$ADMIN_ROOT"/{logs,state,backups}

echo "[4/5] Publish scripts into admin filesystem (no Git required for new admins)"

# Copy repo scripts into shared opt
if [ -d "$REPO_ROOT/opt" ]; then
  shopt -s nullglob
  for f in "$REPO_ROOT/opt/"*.sh; do
    install -m 0750 -o root -g "$ADMIN_GROUP" "$f" "$ADMIN_ROOT/opt/$(basename "$f")"
  done
  shopt -u nullglob
else
  echo "WARNING: $REPO_ROOT/opt not found; nothing to publish."
fi

echo "[5/5] Enforce group-friendly defaults (optional ACL)"

# Optional: Default ACL avoids umask problems for files created in writable dirs
if command -v setfacl >/dev/null 2>&1; then
  for d in "$ADMIN_ROOT" "$ADMIN_ROOT/logs" "$ADMIN_ROOT/state" "$ADMIN_ROOT/backups"; do
    setfacl -m  "g:${ADMIN_GROUP}:rwx,o::---" "$d" || true
    setfacl -d -m "g:${ADMIN_GROUP}:rwx,o::---" "$d" || true
  done
else
  echo "NOTE: setfacl not found; skipping ACL defaults (permissions are still locked down)."
fi

echo "DONE."
echo "Admin filesystem: $ADMIN_ROOT"
echo "Scripts published to: $ADMIN_ROOT/opt"
echo "NOTE: users added to '${ADMIN_GROUP}' must log out/in for group membership to apply."
