#!/usr/bin/env bash
set -euo pipefail

# ============================
# Week 2 (Part B): Logging verification script
#
# What it does:
# - Confirms journald is persistent + bounded (retention policy)
# - Shows journal size + recent warnings/errors
# - Dumps recent logs for key services (nginx + your custom units)
# - Confirms logrotate parses and gsx-admin rotation rule is installed
# - Writes an evidence log under /srv/gsx-admin/logs/ for your report
# ============================

ADMIN_ROOT="${ADMIN_ROOT:-/srv/gsx-admin}"
ADMIN_GROUP="${ADMIN_GROUP:-gsx-admin}"

# Services to check (override by passing unit names as args)
DEFAULT_UNITS=(nginx nginx_setup.service)

TS="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_DIR="${ADMIN_ROOT}/logs"
EVIDENCE_FILE="${EVIDENCE_DIR}/week2-logging-verify-${TS}.log"

note() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }

if [[ "${EUID}" -ne 0 ]]; then
  warn "Not running as root. Some journal output may be restricted unless your user is in 'systemd-journal'."
  warn "Recommended: sudo bash opt/07-verify-logging.sh"
fi

install -d -m 2770 -o root -g "$ADMIN_GROUP" "$EVIDENCE_DIR" 2>/dev/null || true

exec > >(tee "$EVIDENCE_FILE") 2>&1

note "Writing evidence to: $EVIDENCE_FILE"
echo

echo "=== 1) journald status + persistence ==="
systemctl is-active systemd-journald && systemctl is-enabled systemd-journald || true

if [[ -d /var/log/journal ]]; then
  echo "OK: /var/log/journal exists (persistent storage likely enabled)"
  ls -ld /var/log/journal
else
  warn "/var/log/journal is missing (journald may be runtime-only)."
fi

echo
echo "--- journald config (effective files) ---"

if command -v systemd-analyze >/dev/null 2>&1; then
  # Shows config values and where they come from (handy for explaining 'why')
  systemd-analyze cat-config systemd/journald.conf 2>/dev/null | sed -n '1,220p' || true
else
  # Fallback
  grep -R "^[[:space:]]*\(Storage\|SystemMaxUse\|SystemKeepFree\|SystemMaxFileSize\|MaxFileSec\)" \
    /etc/systemd/journald.conf /etc/systemd/journald.conf.d/*.conf 2>/dev/null || true
fi

echo
echo "--- journald disk usage ---"
journalctl --disk-usage || true

echo
echo "=== 2) recent warnings/errors (last 24h) ==="
journalctl -p warning..alert --since "24 hours ago" -n 200 --no-pager -o short-iso || true

echo
echo "=== 3) per-service log excerpts ==="

UNITS=("${@:-${DEFAULT_UNITS[@]}}")
for u in "${UNITS[@]}"; do
  echo
  echo "--- unit: $u (status) ---"
  systemctl status "$u" --no-pager || true

  echo
  echo "--- unit: $u (journal, last 120 lines) ---"
  journalctl -u "$u" -n 120 --no-pager -o short-iso || true
done

echo
echo "=== 4) logrotate checks ==="

if command -v logrotate >/dev/null 2>&1; then
  if [[ -f /etc/logrotate.d/gsx-admin ]]; then
    echo "OK: /etc/logrotate.d/gsx-admin exists"
    sed -n '1,220p' /etc/logrotate.d/gsx-admin
  else
    warn "Missing: /etc/logrotate.d/gsx-admin (run opt/06-logging-observability.sh)"
  fi

  echo
  echo "--- logrotate parse (debug mode; does NOT rotate) ---"
  logrotate -d /etc/logrotate.conf >/dev/null && echo "OK: logrotate config parses" || warn "logrotate parse failed"
else
  warn "logrotate not installed"
fi

echo
echo "=== 5) summary ==="
echo "Evidence file: $EVIDENCE_FILE"
echo "Next steps (if something is missing):"
echo "  - Run: sudo bash opt/06-logging-observability.sh"
echo "  - Re-run: sudo bash opt/07-verify-logging.sh"
