#!/usr/bin/env bash
set -euo pipefail

# ============================
# Week 2 (Part C): Verification
#
# Evidence that:
# - the backup timer is enabled and scheduled
# - backups are running (last run) and producing artifacts
# - logs exist in journald to diagnose failures
#
# Output is written to /srv/gsx-admin/logs/backups for your report/demo.
# ============================

ADMIN_ROOT="${ADMIN_ROOT:-/srv/gsx-admin}"
ADMIN_GROUP="${ADMIN_GROUP:-gsx-admin}"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${ADMIN_ROOT}/logs/backups/week2-backup-verify-${TS}.log"

fail() { echo "ERROR: $*" >&2; exit 1; }

if [[ "${EUID}" -ne 0 ]]; then
  fail "Run as root (sudo)."
fi

grp="$ADMIN_GROUP"
getent group "$grp" >/dev/null 2>&1 || grp="root"
install -d -m 2770 -o root -g "$grp" "${ADMIN_ROOT}/logs" || true
install -d -m 2770 -o root -g "$grp" "${ADMIN_ROOT}/logs/backups" || true

{
  echo "=== GSX Week 2 (Part C) - Backup Verification ==="
  echo "UTC time: $(date -u)"
  echo

  echo "--- systemd timer/service status ---"
  systemctl is-enabled gsx-backup.timer || true
  systemctl is-active  gsx-backup.timer || true
  systemctl status gsx-backup.timer --no-pager || true
  echo

  echo "--- list-timers (gsx-backup) ---"
  systemctl list-timers --all | grep -E "gsx-backup\.timer" || true
  echo

  echo "--- last 80 log lines for backup service ---"
  journalctl -u gsx-backup.service -n 80 --no-pager || true
  echo

  echo "--- last run result (systemctl show) ---"
  systemctl show gsx-backup.service \
    -p ExecMainStatus -p ExecMainCode -p Result -p ActiveEnterTimestamp -p ActiveExitTimestamp || true
  echo

  echo "--- backup artifacts (latest 10) ---"
  ls -lah "${ADMIN_ROOT}/backups" 2>/dev/null || true
  echo
  ls -lt "${ADMIN_ROOT}/backups" 2>/dev/null | head -n 15 || true
  echo

  echo "--- sanity: most recent backup file + checksum ---"
  latest_tar="$(ls -1t "${ADMIN_ROOT}/backups"/week1-sensitive-*.tar 2>/dev/null | head -n 1 || true)"
  latest_gpg="$(ls -1t "${ADMIN_ROOT}/backups"/week1-sensitive-*.tar.gpg 2>/dev/null | head -n 1 || true)"
  if [[ -n "$latest_gpg" ]]; then
    echo "Latest encrypted backup: $latest_gpg"
    sha="${latest_gpg}.sha256"
    if [[ -f "$sha" ]]; then
      echo "Checksum present: $sha"
      sha256sum -c "$sha" || true
    else
      echo "WARNING: checksum missing: $sha"
    fi
  elif [[ -n "$latest_tar" ]]; then
    echo "Latest plaintext backup: $latest_tar"
    sha="${latest_tar}.sha256"
    if [[ -f "$sha" ]]; then
      echo "Checksum present: $sha"
      sha256sum -c "$sha" || true
    else
      echo "WARNING: checksum missing: $sha"
    fi
  else
    echo "WARNING: no backup artifacts found under ${ADMIN_ROOT}/backups"
  fi

  echo
  echo "=== END ==="
} | tee "$OUT"

echo
echo "Evidence saved to: $OUT"
