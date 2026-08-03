
#!/usr/bin/env bash
set -euo pipefail

LOCK_FILE="/var/lock/gsx-week4.lock"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${1:-}"
if [[ -z "$REPO_DIR" ]]; then
  if [[ -d "${SCRIPT_DIR}/../.git" ]]; then
    REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
  elif [[ -d "/home/gsx/gsx-admin/.git" ]]; then
    REPO_DIR="/home/gsx/gsx-admin"
  else
    REPO_DIR="$(pwd)"
  fi
fi

REPO_OWNER="$(stat -c '%U' "$REPO_DIR" 2>/dev/null || echo "gsx")"
ADMIN_ROOT="${ADMIN_ROOT:-/srv/gsx-admin}"
ADMIN_GROUP="${ADMIN_GROUP:-gsx-admin}"
DEV_GROUP="${DEV_GROUP:-greendevcorp}"
TEAM_ROOT="${TEAM_ROOT:-/home/greendevcorp}"
TEAM_BIN="${TEAM_ROOT}/bin"
TEAM_SHARED="${TEAM_ROOT}/shared"
TEAM_DONE_LOG="${TEAM_ROOT}/done.log"
TEAM_PROFILE_SYSTEM="/etc/profile.d/greendevcorp.sh"
TEAM_PROFILE_REPO="${REPO_DIR}/etc/profile.d/greendevcorp.sh"
LIMITS_CONF="/etc/security/limits.conf"
PAM_COMMON_SESSION="/etc/pam.d/common-session"
PAM_COMMON_SESSION_NONINT="/etc/pam.d/common-session-noninteractive"

IFS=' ' read -r -a DEV_USERS <<< "${GSX_DEV_USERS:-dev1 dev2 dev3 dev4}"
PRIMARY_WRITER="${PRIMARY_WRITER:-dev1}"

GSX_NOFILE_SOFT="${GSX_NOFILE_SOFT:-128}"
GSX_NOFILE_HARD="${GSX_NOFILE_HARD:-256}"
GSX_NPROC_SOFT="${GSX_NPROC_SOFT:-64}"
GSX_NPROC_HARD="${GSX_NPROC_HARD:-128}"
GSX_AS_SOFT="${GSX_AS_SOFT:-524288}"
GSX_AS_HARD="${GSX_AS_HARD:-786432}"
GSX_CPU_SOFT="${GSX_CPU_SOFT:-10}"
GSX_CPU_HARD="${GSX_CPU_HARD:-15}"

fail() { echo "ERROR: $*" >&2; exit 1; }

mirror_etc_file() {
  local src="$1"
  [[ -f "$src" ]] || fail "Missing source file to mirror: $src"

  install -D -m 0644 -o "$REPO_OWNER" -g "$REPO_OWNER" "$src" "${REPO_DIR}${src}"

  local grp="$ADMIN_GROUP"
  if ! getent group "$grp" >/dev/null 2>&1; then
    grp="root"
  fi
  install -D -m 0664 -o root -g "$grp" "$src" "${ADMIN_ROOT}${src}"
}

publish_script() {
  local name="$1"
  local src="${REPO_DIR}/opt/${name}"
  [[ -f "$src" ]] || fail "Missing script in repo: $src"

  local grp="$ADMIN_GROUP"
  if ! getent group "$grp" >/dev/null 2>&1; then
    grp="root"
  fi
  install -D -m 0750 -o root -g "$grp" "$src" "${ADMIN_ROOT}/opt/${name}"
}

ensure_pam_limits() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  if grep -Eq '^\s*session\s+required\s+pam_limits\.so\b' "$f"; then
    return 0
  fi
  printf '\n# GSX Week4: enable PAM limits\nsession required pam_limits.so\n' >> "$f"
}

upsert_limits_block() {
  local f="$1"
  local start="# --- GSX Week4 greendevcorp limits (managed) ---"
  local end="# --- end GSX Week4 greendevcorp limits ---"
  local tmp
  tmp="$(mktemp)"

  local block
  block="${start}
# Apply per-user login limits to the GreenDevCorp development team.
# These are inherited through PAM sessions (pam_limits.so).
@${DEV_GROUP} soft nofile ${GSX_NOFILE_SOFT}
@${DEV_GROUP} hard nofile ${GSX_NOFILE_HARD}
@${DEV_GROUP} soft nproc  ${GSX_NPROC_SOFT}
@${DEV_GROUP} hard nproc  ${GSX_NPROC_HARD}
@${DEV_GROUP} soft as     ${GSX_AS_SOFT}
@${DEV_GROUP} hard as     ${GSX_AS_HARD}
@${DEV_GROUP} soft cpu    ${GSX_CPU_SOFT}
@${DEV_GROUP} hard cpu    ${GSX_CPU_HARD}
${end}"

  if grep -Fq "$start" "$f" && grep -Fq "$end" "$f"; then
    awk -v start="$start" -v end="$end" -v block="$block" '
      BEGIN { inblk=0 }
      $0==start { print block; inblk=1; next }
      $0==end   { inblk=0; next }
      inblk==0  { print }
    ' "$f" > "$tmp"
  else
    cat "$f" > "$tmp"
    printf '\n%s\n' "$block" >> "$tmp"
  fi

  if ! cmp -s "$f" "$tmp"; then
    cp -a "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)" || true
    install -m 0644 -o root -g root "$tmp" "$f"
  fi
  rm -f "$tmp"
}

if [[ "${EUID}" -ne 0 ]]; then
  fail "Run as root (sudo)."
fi

if [[ ! -d "$REPO_DIR" ]]; then
  fail "Repo dir not found: $REPO_DIR"
fi

exec 9>"$LOCK_FILE"
flock -n 9 || { echo "Week 4 setup already running. Exiting."; exit 1; }

export DEBIAN_FRONTEND=noninteractive

echo "[1/8] Ensure required package for POSIX ACLs is installed..."
apt-get update -y
apt-get install -y acl >/dev/null

echo "[2/8] Create developer team group and accounts..."
groupadd -f "$DEV_GROUP"
for user in "${DEV_USERS[@]}"; do
  if id "$user" >/dev/null 2>&1; then
    usermod -aG "$DEV_GROUP" "$user"
  else
    useradd -m -s /bin/bash "$user"
    usermod -aG "$DEV_GROUP" "$user"
  fi
  install -d -m 0700 -o "$user" -g "$user" "/home/${user}"
done

id "$PRIMARY_WRITER" >/dev/null 2>&1 || fail "Primary writer user does not exist: $PRIMARY_WRITER"

echo "[3/8] Build shared GreenDevCorp workspace under ${TEAM_ROOT}..."
install -d -m 2750 -o root -g "$DEV_GROUP" "$TEAM_ROOT"
install -d -m 2750 -o root -g "$DEV_GROUP" "$TEAM_BIN"
install -d -m 3770 -o root -g "$DEV_GROUP" "$TEAM_SHARED"

cat > "${TEAM_BIN}/team-env-check" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "team-user=$(id -un)"
echo "team-groups=$(id -nG)"
echo "team-shared=/home/greendevcorp/shared"
EOF
chown root:"$DEV_GROUP" "${TEAM_BIN}/team-env-check"
chmod 0750 "${TEAM_BIN}/team-env-check"

if [[ ! -f "$TEAM_DONE_LOG" ]]; then
  install -m 0640 -o "$PRIMARY_WRITER" -g "$DEV_GROUP" /dev/null "$TEAM_DONE_LOG"
fi
chown "$PRIMARY_WRITER":"$DEV_GROUP" "$TEAM_DONE_LOG"
chmod 0640 "$TEAM_DONE_LOG"
if [[ ! -s "$TEAM_DONE_LOG" ]]; then
  printf '%s\n' "$(date '+%F %T') bootstrap - GreenDevCorp workspace initialized" > "$TEAM_DONE_LOG"
  chown "$PRIMARY_WRITER":"$DEV_GROUP" "$TEAM_DONE_LOG"
  chmod 0640 "$TEAM_DONE_LOG"
fi

if command -v setfacl >/dev/null 2>&1; then
  setfacl -b "$TEAM_SHARED" "$TEAM_DONE_LOG" || true
  setfacl -m "g:${DEV_GROUP}:rwx" "$TEAM_SHARED" || true
  setfacl -d -m "g:${DEV_GROUP}:rwx" "$TEAM_SHARED" || true
  setfacl -m "u:${PRIMARY_WRITER}:rw-,g:${DEV_GROUP}:r--,o::---" "$TEAM_DONE_LOG" || true
fi

echo "[4/8] Install shared profile.d environment for team members..."
if [[ -f "$TEAM_PROFILE_REPO" ]]; then
  install -D -m 0644 -o root -g root "$TEAM_PROFILE_REPO" "$TEAM_PROFILE_SYSTEM"
else
  cat > "$TEAM_PROFILE_SYSTEM" <<'EOF'
#!/usr/bin/env bash
if id -nG 2>/dev/null | grep -qw greendevcorp; then
  case ":${PATH}:" in
    *:/home/greendevcorp/bin:*) ;;
    *) PATH="/home/greendevcorp/bin:${PATH}" ;;
  esac
  export PATH
  umask 0027
  alias ll='ls -alF --color=auto'
  alias cdtm='cd /home/greendevcorp/shared'
  alias donelog='tail -n 20 /home/greendevcorp/done.log'
fi
EOF
fi
chmod 0644 "$TEAM_PROFILE_SYSTEM"

echo "[5/8] Configure PAM user limits for ${DEV_GROUP}..."
upsert_limits_block "$LIMITS_CONF"
ensure_pam_limits "$PAM_COMMON_SESSION"
ensure_pam_limits "$PAM_COMMON_SESSION_NONINT"

echo "[6/8] Mirror tracked system configuration into repo and admin share..."
local_admin_group="$ADMIN_GROUP"
if ! getent group "$local_admin_group" >/dev/null 2>&1; then
  local_admin_group="root"
fi
install -d -m 2750 -o root -g "$local_admin_group" "$ADMIN_ROOT" || true
install -d -m 2750 -o root -g "$local_admin_group" "$ADMIN_ROOT/opt" "$ADMIN_ROOT/etc" "$ADMIN_ROOT/docs" 2>/dev/null || true

mirror_etc_file "$TEAM_PROFILE_SYSTEM"
mirror_etc_file "$LIMITS_CONF"

echo "[7/8] Publish Week 4 scripts into ${ADMIN_ROOT}/opt..."
publish_script "15-week4-users-groups-setup.sh"
publish_script "16-verify-week4-security.sh"

echo "[8/8] Summary"
echo "- Team group: ${DEV_GROUP}"
echo "- Users     : ${DEV_USERS[*]}"
echo "- Team root : ${TEAM_ROOT}"
echo "- Shared dir: ${TEAM_SHARED} (setgid + sticky)"
echo "- done.log  : ${TEAM_DONE_LOG} (append allowed only to ${PRIMARY_WRITER})"
echo "- Profile   : ${TEAM_PROFILE_SYSTEM}"
echo "- Limits    : ${LIMITS_CONF}"
echo
echo "NOTE: users need a new login session before PATH and PAM limits are visible."
