#!/usr/bin/env bash
set -euo pipefail

LOCK_FILE="/var/lock/gsx-week1.lock"

GSX_REPO_ROOT="${GSX_REPO_ROOT:-/home/gsx/gsx-admin}"
GSX_REPO_OWNER="${GSX_REPO_OWNER:-gsx}"
GSX_GIT_REMOTE="${GSX_GIT_REMOTE:-}"   # <- no hardcoded URL

# Root required (initial setup)
if [ "${EUID}" -ne 0 ]; then
  echo "ERROR: Run as root (initial setup)."
  exit 1
fi

# Acquire lock once
exec 9>"$LOCK_FILE"
flock -n 9 || { echo "Setup already running. Exiting."; exit 1; }

export DEBIAN_FRONTEND=noninteractive
export GIT_TERMINAL_PROMPT=0   # never block for git credentials

echo "[1/7] Install minimal prereqs for cloning (git + certs)..."
apt-get update -y
apt-get install -y git ca-certificates util-linux

echo "[2/7] Repo clone URL"
if [ -z "$GSX_GIT_REMOTE" ]; then
  read -r -p "Git repo HTTPS clone URL (e.g. https://github.com/user/repo.git): " GSX_GIT_REMOTE
fi
if [ -z "$GSX_GIT_REMOTE" ]; then
  echo "ERROR: repo URL is required."
  exit 1
fi
export GSX_GIT_REMOTE

echo "[3/7] GitHub credentials (optional)"
echo "  - If the repo is PUBLIC, just press Enter twice."
read -r -p "GitHub username (or blank): " GH_USER
read -r -s -p "GitHub token/PAT (or blank): " GH_TOKEN
echo

# Build an auth header if token provided (kept only in memory)
GSX_GIT_AUTH_HEADER=""
if [ -n "$GH_TOKEN" ]; then
  # NOTE: Token-based auth here is for HTTPS remotes.
  GH_USER="${GH_USER:-x-access-token}"
  B64="$(printf '%s:%s' "$GH_USER" "$GH_TOKEN" | base64 -w0)"
  GSX_GIT_AUTH_HEADER="Authorization: Basic $B64"
  export GSX_GIT_AUTH_HEADER
  unset GH_TOKEN
fi

echo "[4/7] Ensure user '${GSX_REPO_OWNER}' exists..."
if ! id "$GSX_REPO_OWNER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$GSX_REPO_OWNER"
  echo "  - Created user: ${GSX_REPO_OWNER}"
fi

echo "[5/7] Clone or update repo in: ${GSX_REPO_ROOT}"
PARENT_DIR="$(dirname "$GSX_REPO_ROOT")"
install -d -m 0755 "$PARENT_DIR"
chown "$GSX_REPO_OWNER:$GSX_REPO_OWNER" "$PARENT_DIR" || true

git_as_owner() {
  # Runs git as the repo owner, optionally with auth header
  if [ -n "${GSX_GIT_AUTH_HEADER}" ]; then
    runuser -u "$GSX_REPO_OWNER" -- git -c "http.extraHeader=${GSX_GIT_AUTH_HEADER}" "$@"
  else
    runuser -u "$GSX_REPO_OWNER" -- git "$@"
  fi
}

if [ -d "$GSX_REPO_ROOT/.git" ]; then
  echo "  - Repo already present; attempting fast-forward pull."
  git_as_owner -C "$GSX_REPO_ROOT" remote set-url origin "$GSX_GIT_REMOTE" >/dev/null 2>&1 || true
  git_as_owner -C "$GSX_REPO_ROOT" pull --ff-only || \
    echo "WARNING: pull failed (auth/local changes). Continuing with existing content."
elif [ -e "$GSX_REPO_ROOT" ]; then
  echo "ERROR: ${GSX_REPO_ROOT} exists but is not a git repo."
  exit 1
else
  git_as_owner clone "$GSX_GIT_REMOTE" "$GSX_REPO_ROOT" || {
    echo "ERROR: clone failed."
    echo "If the repo is private, rerun and provide a valid PAT."
    exit 1
  }
  # Ensure origin is set to the exact URL you entered (clean, no token embedded)
  git_as_owner -C "$GSX_REPO_ROOT" remote set-url origin "$GSX_GIT_REMOTE" >/dev/null 2>&1 || true
fi

# Ensure repo not owned by root
chown -R "$GSX_REPO_OWNER:$GSX_REPO_OWNER" "$GSX_REPO_ROOT" || true

echo "[6/7] Run 01 then 02 from the repo."
REPO_01="$GSX_REPO_ROOT/opt/01-install-packages.sh"
REPO_02="$GSX_REPO_ROOT/opt/02-setup-admin-dirs.sh"

[ -f "$REPO_01" ] || { echo "ERROR: missing $REPO_01"; exit 1; }
[ -f "$REPO_02" ] || { echo "ERROR: missing $REPO_02"; exit 1; }

GSX_PARENT_LOCK=1 GSX_REPO_ROOT="$GSX_REPO_ROOT" GSX_REPO_OWNER="$GSX_REPO_OWNER" GSX_GIT_REMOTE="$GSX_GIT_REMOTE" bash "$REPO_01"
GSX_PARENT_LOCK=1 bash "$REPO_02"

echo "[7/7] Verify critical state."

# SSH service active/enabled
systemctl is-enabled ssh >/dev/null 2>&1 || systemctl is-enabled sshd >/dev/null 2>&1
systemctl is-active  ssh >/dev/null 2>&1 || systemctl is-active  sshd >/dev/null 2>&1

# Verify listening port from config created by 01
SYS_SSH="/etc/ssh/sshd_config.d/gsx-hardening.conf"
[ -f "$SYS_SSH" ] || { echo "ERROR: missing $SYS_SSH"; exit 1; }
PORT="$(awk '$1=="Port"{print $2}' "$SYS_SSH" | tail -n1)"
PORT="${PORT:-22}"
ss -tlnp | grep -q ":${PORT} " || { echo "ERROR: sshd not listening on port ${PORT}"; exit 1; }

# Verify sudoers drop-in for gsx-admin (created by 02)
SUDOERS_FILE="/etc/sudoers.d/gsx-admin"
[ -f "$SUDOERS_FILE" ] || { echo "ERROR: missing $SUDOERS_FILE"; exit 1; }
command -v visudo >/dev/null 2>&1 && visudo -cf "$SUDOERS_FILE" >/dev/null || true

getent group gsx-admin >/dev/null || { echo "ERROR: gsx-admin group missing"; exit 1; }

echo "OK: Initial initialization verified."
