#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Week 3 (Part C): Resource Limits
#
# - Configure per-user limits via PAM (/etc/security/limits.conf)
# - Configure a systemd service (workload) with CPU/memory limits (cgroups)
# - Mirror edited /etc files into:
#   - repo:        /home/$user/gsx-admin/etc/...
#   - admin share: /srv/gsx-admin/etc/...
# -----------------------------

# Repo path: prefer arg1, otherwise try to auto-detect
REPO_DIR="${1:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "$REPO_DIR" ]]; then
  # If running from inside the repo (opt/), parent should have .git
  if [[ -d "${SCRIPT_DIR}/../.git" ]]; then
    REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
  elif [[ -d "/home/gsx/gsx-admin/.git" ]]; then
    REPO_DIR="/home/gsx/gsx-admin"
  else
    REPO_DIR="$(pwd)"
  fi
fi

# Detect repo owner to run git as that user
GIT_USER="$(stat -c '%U' "$REPO_DIR" 2>/dev/null || echo "gsx")"

# Shared admin directory (gsx-admin group directory)
ADMIN_DIR="/srv/gsx-admin"

# --- Week 3 workload service ---
UNIT_NAME="gsx-workload"
SERVICE_FILE="/etc/systemd/system/${UNIT_NAME}.service"

# --- PAM / limits ---
LIMITS_CONF="/etc/security/limits.conf"
PAM_COMMON_SESSION="/etc/pam.d/common-session"
PAM_COMMON_SESSION_NONINT="/etc/pam.d/common-session-noninteractive"

# Tunables (override via env)
GSX_CPU_QUOTA="${GSX_CPU_QUOTA:-25%}"
GSX_MEMORY_MAX="${GSX_MEMORY_MAX:-200M}"
GSX_TASKS_MAX="${GSX_TASKS_MAX:-200}"
GSX_WORKERS="${GSX_WORKERS:-6}"
GSX_NICE="${GSX_NICE:-15}"

fail() { echo "ERROR: $*" >&2; exit 1; }

mirror_etc_file() {
  # Mirrors an absolute path like /etc/systemd/system/X into:
  #   $REPO_DIR/etc/systemd/system/X
  #   $ADMIN_DIR/etc/systemd/system/X
  local src="$1"

  [[ -f "$src" ]] || fail "Source file does not exist: $src"

  # Repo mirror (owned by repo user)
  install -D -m 0644 -o "$GIT_USER" -g "$GIT_USER" \
    "$src" "${REPO_DIR}${src}"

  # Admin shared mirror (root:gsx-admin, group-writable)
  local grp="gsx-admin"
  if ! getent group "$grp" >/dev/null 2>&1; then
    grp="root"
  fi

  install -D -m 0664 -o root -g "$grp" \
    "$src" "${ADMIN_DIR}${src}"
}

ensure_pam_limits() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  if grep -Eq '^\s*session\s+required\s+pam_limits\.so\b' "$f"; then
    return 0
  fi
  echo "Adding pam_limits.so to: $f"
  printf '\n# GSX Week3: enable PAM limits\nsession required pam_limits.so\n' >> "$f"
}

upsert_limits_block() {
  # Add/replace a clearly delimited block inside /etc/security/limits.conf
  local f="$1"
  local start="# --- GSX Week3 limits (managed) ---"
  local end="# --- end GSX Week3 limits ---"

  [[ -f "$f" ]] || fail "Missing: $f"

  local tmp
  tmp="$(mktemp)"

  # Content we want (soft/hard)
  # NOTE: conservative values for a small VM; adjust if needed.
  local block
  block="${start}
# Apply limits to the admin group (PAM sessions only)
@gsx-admin soft nofile 2048
@gsx-admin hard nofile 8192
@gsx-admin soft nproc  512
@gsx-admin hard nproc  1024
${end}"

  if grep -Fq "$start" "$f" && grep -Fq "$end" "$f"; then
    # Replace existing managed block
    awk -v start="$start" -v end="$end" -v block="$block" '
      BEGIN{inblk=0}
      $0==start {print block; inblk=1; next}
      $0==end   {inblk=0; next}
      inblk==0  {print}
    ' "$f" > "$tmp"
  else
    # Append block
    cat "$f" > "$tmp"
    printf '\n%s\n' "$block" >> "$tmp"
  fi

  # Only write if changed
  if ! cmp -s "$f" "$tmp"; then
    cp -a "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)" || true
    install -m 0644 -o root -g root "$tmp" "$f"
  fi
  rm -f "$tmp"
}

if [[ $EUID -ne 0 ]]; then
  fail "este script debe ejecutarse como root (usa sudo)."
fi

if [[ ! -d "$REPO_DIR" ]]; then
  fail "REPO_DIR no existe: $REPO_DIR"
fi

echo "[1/9] Preparing workload runtime paths (/srv/gsx-admin)..."

# Ensure /srv/gsx-admin has the workload script and required dirs
grp="gsx-admin"
if ! getent group "$grp" >/dev/null 2>&1; then
  grp="root"
fi
install -d -m 2775 -o root -g "$grp" "${ADMIN_DIR}/opt" "${ADMIN_DIR}/etc/gsx-admin" "${ADMIN_DIR}/logs/workload" 2>/dev/null || true

# Copy workload script into /srv so the service has a stable path
if [[ -f "${REPO_DIR}/opt/11-workload-signals.sh" ]]; then
  install -m 0755 -o root -g "$grp" "${REPO_DIR}/opt/11-workload-signals.sh" "${ADMIN_DIR}/opt/11-workload-signals.sh"
else
  fail "Missing workload script in repo: ${REPO_DIR}/opt/11-workload-signals.sh"
fi

echo "[2/9] Creating workload systemd service with resource limits (cgroups)..."

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=GSX Week3 Workload (signals + cgroups resource limits)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple

# Run as non-root (safer). User must be in gsx-admin group.
User=gsx
Group=gsx-admin

WorkingDirectory=/srv/gsx-admin

# Resource accounting (needed for systemctl to show usage)
CPUAccounting=yes
MemoryAccounting=yes
TasksAccounting=yes

# Resource limits (cgroups)
CPUQuota=${GSX_CPU_QUOTA}
MemoryMax=${GSX_MEMORY_MAX}
TasksMax=${GSX_TASKS_MAX}

# Graceful shutdown: let the manager handle workers (SIGTERM)
KillSignal=SIGTERM
TimeoutStopSec=15
KillMode=mixed

# Basic hardening (keep it compatible with /srv/gsx-admin)
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/srv/gsx-admin

# Dedicated runtime dir for PID file
RuntimeDirectory=gsx-workload
RuntimeDirectoryMode=0750

ExecStart=/usr/bin/bash /srv/gsx-admin/opt/11-workload-signals.sh \
  --workers ${GSX_WORKERS} \
  --nice ${GSX_NICE} \
  --output /dev/null \
  --config /srv/gsx-admin/etc/gsx-admin/workload.conf \
  --pidfile /run/gsx-workload/gsx-workload-manager.pid \
  --log /srv/gsx-admin/logs/workload/workload-manager.log

Restart=on-failure
RestartSec=2

SyslogIdentifier=gsx-workload

[Install]
WantedBy=multi-user.target
EOF

echo "[3/9] Configure PAM limits (limits.conf + pam_limits.so)..."

upsert_limits_block "$LIMITS_CONF"

# Ensure pam_limits is enabled (common-session files)
before_cs="$(sha256sum "$PAM_COMMON_SESSION" 2>/dev/null | awk '{print $1}' || true)"
before_csn="$(sha256sum "$PAM_COMMON_SESSION_NONINT" 2>/dev/null | awk '{print $1}' || true)"

ensure_pam_limits "$PAM_COMMON_SESSION"
ensure_pam_limits "$PAM_COMMON_SESSION_NONINT"

after_cs="$(sha256sum "$PAM_COMMON_SESSION" 2>/dev/null | awk '{print $1}' || true)"
after_csn="$(sha256sum "$PAM_COMMON_SESSION_NONINT" 2>/dev/null | awk '{print $1}' || true)"

echo "[4/9] Reload systemd + enable workload service..."
systemctl daemon-reload
systemctl enable --now "${UNIT_NAME}.service"

# Give systemd a moment; then fail fast with diagnostics if it did not start
sleep 1
if ! systemctl is-active --quiet "${UNIT_NAME}.service"; then
  echo "\nERROR: ${UNIT_NAME}.service did not start successfully." >&2
  systemctl status "${UNIT_NAME}.service" --no-pager >&2 || true
  echo "\n--- journalctl -u ${UNIT_NAME}.service (last 120 lines) ---" >&2
  journalctl -u "${UNIT_NAME}.service" -b --no-pager -n 120 >&2 || true
  exit 1
fi

echo "[5/9] Mirroring edited /etc files into repo and admin share..."
mirror_etc_file "$SERVICE_FILE"
mirror_etc_file "$LIMITS_CONF"

if [[ "$before_cs" != "$after_cs" ]]; then
  mirror_etc_file "$PAM_COMMON_SESSION"
fi
if [[ "$before_csn" != "$after_csn" ]]; then
  mirror_etc_file "$PAM_COMMON_SESSION_NONINT"
fi

echo "[6/9] Quick verification (service + cgroup controls)..."
systemctl is-active "${UNIT_NAME}.service" >/dev/null || fail "${UNIT_NAME}.service is not active"

CGROUP="$(systemctl show "${UNIT_NAME}.service" -p ControlGroup --value)"
echo "ControlGroup: $CGROUP"
if [[ -n "$CGROUP" && -d "/sys/fs/cgroup${CGROUP}" ]]; then
  echo "cpu.max:     $(cat "/sys/fs/cgroup${CGROUP}/cpu.max" 2>/dev/null || echo N/A)"
  echo "memory.max:  $(cat "/sys/fs/cgroup${CGROUP}/memory.max" 2>/dev/null || echo N/A)"
  echo "pids.max:    $(cat "/sys/fs/cgroup${CGROUP}/pids.max" 2>/dev/null || echo N/A)"
else
  echo "NOTE: cgroup path not readable (maybe cgroup v1 or restricted)."
fi

echo "[7/9] Git sync (best-effort) ..."
if [[ -d "$REPO_DIR/.git" ]]; then
  add_paths=(
    "etc/systemd/system/${UNIT_NAME}.service"
    "etc/security/limits.conf"
  )
  if [[ "$before_cs" != "$after_cs" ]]; then
    add_paths+=("etc/pam.d/common-session")
  fi
  if [[ "$before_csn" != "$after_csn" ]]; then
    add_paths+=("etc/pam.d/common-session-noninteractive")
  fi

  sudo -u "$GIT_USER" git -C "$REPO_DIR" add "${add_paths[@]}"

  if ! sudo -u "$GIT_USER" git -C "$REPO_DIR" diff --cached --quiet; then
    sudo -u "$GIT_USER" git -C "$REPO_DIR" commit -m "Week3 (Part C): systemd resource limits + PAM ulimit" || \
      echo "WARNING: git commit failed (missing user.name/user.email?). Commit later."
    sudo -u "$GIT_USER" git -C "$REPO_DIR" push origin main || \
      sudo -u "$GIT_USER" git -C "$REPO_DIR" push origin master || true
  else
    echo "No changes to commit."
  fi
else
  echo "NOTE: no .git found at $REPO_DIR; skipping commit/push."
fi

echo "[8/9] How to verify limits are enforced (copy/paste)"
cat <<'EOF'

# Service resource limits (systemd):
systemctl status gsx-workload.service --no-pager
systemctl show gsx-workload.service -p CPUQuota -p MemoryMax -p TasksMax -p ControlGroup

# Evidence via cgroups (cgroup v2):
CG=$(systemctl show gsx-workload.service -p ControlGroup --value)
sudo cat /sys/fs/cgroup${CG}/cpu.max
sudo cat /sys/fs/cgroup${CG}/memory.max
sudo cat /sys/fs/cgroup${CG}/pids.max

# Monitoring:
systemd-cgtop -b -n 1
systemd-cgls /system.slice/gsx-workload.service

# Per-user ulimit (new login shell):
ulimit -Sn; ulimit -Hn; ulimit -Su; ulimit -Hu
EOF

echo "[9/9] DONE."
echo "Service: ${UNIT_NAME}.service (CPUQuota=${GSX_CPU_QUOTA}, MemoryMax=${GSX_MEMORY_MAX})"
