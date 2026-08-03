#!/usr/bin/env bash
set -euo pipefail

# =========================
# Config (override via env)
# =========================
ADMIN_GROUP="${ADMIN_GROUP:-gsx-admin}"
ADMIN_ROOT="${ADMIN_ROOT:-/srv/gsx-admin}"
BACKUP_DIR="${BACKUP_DIR:-${ADMIN_ROOT}/backups}"

# Encryption mode:
# - auto (default):
#     * if PASSPHRASE is set -> non-interactive encryption
#     * else if TTY exists -> interactive prompt
#     * else -> plaintext tar + checksum (so timer doesn't fail)
# - gpg: always encrypt (fails if no PASSPHRASE and no TTY)
# - none: never encrypt (plaintext tar + checksum)
ENCRYPT_MODE="${ENCRYPT_MODE:-auto}"   # auto|gpg|none

LOCK_FILE="/var/lock/gsx-week1.lock"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
BASENAME="week1-sensitive-${TS}"
ARCHIVE="${BACKUP_DIR}/${BASENAME}.tar"
ENCRYPTED="${ARCHIVE}.gpg"
CHECKSUM="${ENCRYPTED}.sha256"
PLAIN_CHECKSUM="${ARCHIVE}.sha256"

# =========================
# Root required
# =========================
if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: Run as root."
  exit 1
fi

# =========================
# Global lock
# =========================
if [[ "${GSX_PARENT_LOCK:-0}" -ne 1 ]]; then
  exec 9>"$LOCK_FILE"
  flock -n 9 || { echo "Setup already running. Exiting."; exit 1; }
fi

umask 077

# If group doesn't exist, fall back to root to avoid hard failure
if ! getent group "${ADMIN_GROUP}" >/dev/null 2>&1; then
  echo "WARNING: group '${ADMIN_GROUP}' not found; using root."
  ADMIN_GROUP="root"
fi

install -d -m 2770 -o root -g "${ADMIN_GROUP}" "${BACKUP_DIR}"

# =========================
# Include paths
# =========================
INCLUDES=(
  /etc/ssh
  /etc/sudoers
  /etc/sudoers.d
  /etc/hostname
  /etc/hosts
  "${ADMIN_ROOT}"
  /home/gsx/.ssh
)

EXISTING=()
for p in "${INCLUDES[@]}"; do
  if [[ -e "$p" ]]; then
    EXISTING+=("$p")
  else
    echo "NOTE: missing path (skipped): $p"
  fi
done

if [[ "${#EXISTING[@]}" -eq 0 ]]; then
  echo "ERROR: nothing to back up (all include paths missing)."
  exit 1
fi

echo "Creating archive: ${ARCHIVE}"

# Exclude volatile areas + prevent archive containing itself
# (logs/state often change during backup, can trigger tar warnings)
set +e
tar --create --file "${ARCHIVE}" \
  --numeric-owner --preserve-permissions \
  --xattrs --acls \
  --exclude="${BACKUP_DIR}" --exclude="${BACKUP_DIR}/*" \
  --exclude="${ADMIN_ROOT}/logs" --exclude="${ADMIN_ROOT}/logs/*" \
  --exclude="${ADMIN_ROOT}/state" --exclude="${ADMIN_ROOT}/state/*" \
  "${EXISTING[@]}"
tar_rc=$?
set -e

# tar exits 1 for some warnings; treat rc>1 as real failure
if [[ "$tar_rc" -gt 1 ]]; then
  echo "ERROR: tar failed with exit code ${tar_rc}"
  exit "$tar_rc"
fi

HAS_TTY=0
if [[ -t 0 && -t 1 ]]; then
  HAS_TTY=1
fi

do_encrypt=0
case "$ENCRYPT_MODE" in
  none) do_encrypt=0 ;;
  gpg)  do_encrypt=1 ;;
  auto)
    if [[ -n "${PASSPHRASE:-}" || "$HAS_TTY" -eq 1 ]]; then
      do_encrypt=1
    else
      do_encrypt=0
    fi
    ;;
  *)
    echo "ERROR: invalid ENCRYPT_MODE='$ENCRYPT_MODE' (use auto|gpg|none)"
    exit 1
    ;;
esac

if [[ "$do_encrypt" -eq 1 ]]; then
  echo "Encrypting archive with GPG (AES256) -> ${ENCRYPTED}"

  # Only set GPG_TTY if a TTY exists (systemd services usually don't have one)
  if [[ "$HAS_TTY" -eq 1 ]]; then
    export GPG_TTY="$(tty)"
  fi
  gpgconf --launch gpg-agent >/dev/null 2>&1 || true

  if [[ -n "${PASSPHRASE:-}" ]]; then
    # Avoid exposing passphrase in process args by using passphrase-fd
    printf '%s' "${PASSPHRASE}" | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 \
      --symmetric --cipher-algo AES256 --output "${ENCRYPTED}" "${ARCHIVE}"
  else
    if [[ "$HAS_TTY" -ne 1 ]]; then
      echo "ERROR: ENCRYPT_MODE=${ENCRYPT_MODE} but no PASSPHRASE and no TTY (timer run)."
      exit 1
    fi
    gpg --yes --symmetric --cipher-algo AES256 --output "${ENCRYPTED}" "${ARCHIVE}"
  fi

  sha256sum "${ENCRYPTED}" > "${CHECKSUM}"
  rm -f "${ARCHIVE}"

  echo "DONE."
  echo "Encrypted backup : ${ENCRYPTED}"
  echo "Checksum file    : ${CHECKSUM}"
  echo "Backup directory : ${BACKUP_DIR}"
else
  echo "NOTE: encryption disabled (ENCRYPT_MODE=${ENCRYPT_MODE})."
  sha256sum "${ARCHIVE}" > "${PLAIN_CHECKSUM}"

  echo "DONE."
  echo "Plain backup     : ${ARCHIVE}"
  echo "Checksum file    : ${PLAIN_CHECKSUM}"
  echo "Backup directory : ${BACKUP_DIR}"
fi