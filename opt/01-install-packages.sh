#!/usr/bin/env bash
set -euo pipefail

LOCK_FILE="/var/lock/gsx-week1.lock"

# Local gsx-admin repo root (contains: docs/ etc/ opt/ var/backup/)
GSX_REPO_ROOT="${GSX_REPO_ROOT:-/home/gsx/gsx-admin}"
GSX_REPO_OWNER="${GSX_REPO_OWNER:-gsx}"

# Remote repo (private/public)
GSX_GIT_REMOTE="${GSX_GIT_REMOTE:-https://github.com/davidcaran/gsx-admin.git}"

# If 03 prompted for GitHub creds, it should export this:
#   GSX_GIT_AUTH_HEADER="Authorization: Basic <base64(user:token)>"
GSX_GIT_AUTH_HEADER="${GSX_GIT_AUTH_HEADER:-}"

# Part A requirements
GSX_SSH_PORT="${GSX_SSH_PORT:-2222}"   # change default port (hardening)

# Ensure root (initial setup)
if [ "${EUID}" -ne 0 ]; then
  echo "ERROR: Run as root (initial setup)."
  exit 1
fi

# Lock only when run standalone (03 will set GSX_PARENT_LOCK=1)
if [ "${GSX_PARENT_LOCK:-0}" -ne 1 ]; then
  exec 9>"$LOCK_FILE"
  flock -n 9 || { echo "Setup already running. Exiting."; exit 1; }
fi

export DEBIAN_FRONTEND=noninteractive
export GIT_TERMINAL_PROMPT=0   # never block waiting for credentials

# Helper: run git as the repo owner, optionally injecting an auth header for HTTPS
git_as_owner() {
  if [ -n "$GSX_GIT_AUTH_HEADER" ]; then
    runuser -u "$GSX_REPO_OWNER" -- git -c "http.extraHeader=${GSX_GIT_AUTH_HEADER}" "$@"
  else
    runuser -u "$GSX_REPO_OWNER" -- git "$@"
  fi
}

echo "[1/5] Installing packages..."
apt-get update -y
apt-get install -y \
  sudo \
  openssh-server \
  git \
  unattended-upgrades \
  apt-listchanges \
  ca-certificates \
  curl wget \
  vim nano \
  tmux \
  htop \
  rsync \
  gnupg \
  tree \
  unzip \
  util-linux

systemctl enable --now ssh >/dev/null 2>&1 || systemctl enable --now sshd >/dev/null 2>&1 || true

echo "[2/5] Ensuring repo exists at: ${GSX_REPO_ROOT}"
if [ ! -d "$GSX_REPO_ROOT/.git" ]; then
  echo "ERROR: ${GSX_REPO_ROOT} is not a git repo (no .git)."
  echo "       This should have been cloned by 03-verify.sh before calling 01."
  exit 1
fi

# Ensure /home/gsx repo is not owned by root (avoid 'dubious ownership' + permission pain)
chown -R "$GSX_REPO_OWNER:$GSX_REPO_OWNER" "$GSX_REPO_ROOT" || true

# Ensure repo folders exist
install -d -m 755 "$GSX_REPO_ROOT/etc/ssh/sshd_config.d"
install -d -m 755 "$GSX_REPO_ROOT/etc/apt/apt.conf.d"

echo "[3/5] Writing configs into repo + installing into system..."

# --- A) Enable automatic security updates (repo-backed) ---
REPO_AUTO_UPGRADES="$GSX_REPO_ROOT/etc/apt/apt.conf.d/20auto-upgrades"
cat > "$REPO_AUTO_UPGRADES" <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
chown "$GSX_REPO_OWNER:$GSX_REPO_OWNER" "$REPO_AUTO_UPGRADES" || true

install -d -m 755 /etc/apt/apt.conf.d
install -m 644 "$REPO_AUTO_UPGRADES" /etc/apt/apt.conf.d/20auto-upgrades

dpkg-reconfigure -f noninteractive unattended-upgrades >/dev/null 2>&1 || true
systemctl enable --now apt-daily.timer apt-daily-upgrade.timer >/dev/null 2>&1 || true

# --- B) SSH hardening (repo-backed) ---
# - disable password auth (key-based only)
# - change default port
# - disable root SSH login
REPO_SSH_HARDEN="$GSX_REPO_ROOT/etc/ssh/sshd_config.d/gsx-hardening.conf"
cat > "$REPO_SSH_HARDEN" <<EOF
# GSX Week 1 baseline hardening
Port ${GSX_SSH_PORT}
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM yes
X11Forwarding no
EOF
chown "$GSX_REPO_OWNER:$GSX_REPO_OWNER" "$REPO_SSH_HARDEN" || true

install -d -m 755 /etc/ssh/sshd_config.d
install -m 644 "$REPO_SSH_HARDEN" /etc/ssh/sshd_config.d/gsx-hardening.conf

# Validate + restart ssh
if sshd -t; then
  systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1
else
  echo "ERROR: sshd config validation failed. Not restarting SSH."
  exit 1
fi

echo "[4/5] Committing configs to git (as ${GSX_REPO_OWNER})..."

git_as_owner -C "$GSX_REPO_ROOT" add \
  "etc/apt/apt.conf.d/20auto-upgrades" \
  "etc/ssh/sshd_config.d/gsx-hardening.conf"

if [ -n "$(git_as_owner -C "$GSX_REPO_ROOT" status --porcelain)" ]; then
  # commit might fail if user.name/email aren't set; don't abort the whole setup
  git_as_owner -C "$GSX_REPO_ROOT" commit -m "Week 1 (Part A): SSH hardening + unattended upgrades" || \
    echo "WARNING: git commit failed (maybe missing user.name/user.email). You can commit later."
else
  echo "  - No changes to commit."
fi

echo "[5/5] Pushing to remote (best-effort, non-interactive)..."

# Ensure origin exists and points to the right remote
if git_as_owner -C "$GSX_REPO_ROOT" remote get-url origin >/dev/null 2>&1; then
  git_as_owner -C "$GSX_REPO_ROOT" remote set-url origin "$GSX_GIT_REMOTE" >/dev/null 2>&1 || true
else
  git_as_owner -C "$GSX_REPO_ROOT" remote add origin "$GSX_GIT_REMOTE" >/dev/null 2>&1 || true
fi

CURRENT_BRANCH="$(git_as_owner -C "$GSX_REPO_ROOT" rev-parse --abbrev-ref HEAD)"
git_as_owner -C "$GSX_REPO_ROOT" push -u origin "$CURRENT_BRANCH" || \
  echo "WARNING: push failed (no auth or repo private). This is OK — push later from your laptop."

echo
echo "DONE."
echo "SSH now listens on port: ${GSX_SSH_PORT}"
echo "PasswordAuthentication is DISABLED (key-based only)."
echo "Repo updated: ${GSX_REPO_ROOT}"
