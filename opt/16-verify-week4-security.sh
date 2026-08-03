
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

DEV_GROUP="${DEV_GROUP:-greendevcorp}"
TEAM_ROOT="${TEAM_ROOT:-/home/greendevcorp}"
TEAM_BIN="${TEAM_ROOT}/bin"
TEAM_SHARED="${TEAM_ROOT}/shared"
TEAM_DONE_LOG="${TEAM_ROOT}/done.log"
PRIMARY_WRITER="${PRIMARY_WRITER:-dev1}"
USERS=(dev1 dev2 dev3 dev4)

pass_count=0
fail_count=0
skip_count=0

pass() { echo "PASS: $*"; pass_count=$((pass_count + 1)); }
fail() { echo "FAIL: $*" >&2; fail_count=$((fail_count + 1)); }
skip() { echo "SKIP: $*"; skip_count=$((skip_count + 1)); }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Run as root (sudo)." >&2
    exit 1
  fi
}

limit_from_conf() {
  local item="$1" type="$2"
  awk -v dom="@${DEV_GROUP}" -v type="$type" -v item="$item" '
    $1==dom && $2==type && $3==item { print $4; found=1 }
    END { if (!found) exit 1 }
  ' /etc/security/limits.conf 2>/dev/null || true
}

check_user_in_group() {
  local user="$1"
  id -nG "$user" 2>/dev/null | tr ' ' '\n' | grep -Fxq "$DEV_GROUP"
}

run_as_login() {
  local user="$1"
  shift
  runuser -l "$user" -c "bash -lc '$*'"
}

require_root

echo "== Week 4 verification =="
echo

if getent group "$DEV_GROUP" >/dev/null 2>&1; then
  pass "Group ${DEV_GROUP} exists"
else
  fail "Group ${DEV_GROUP} does not exist"
fi

for user in "${USERS[@]}"; do
  if id "$user" >/dev/null 2>&1; then
    pass "User ${user} exists"
  else
    fail "User ${user} is missing"
    continue
  fi

  if check_user_in_group "$user"; then
    pass "User ${user} is a member of ${DEV_GROUP}"
  else
    fail "User ${user} is not in ${DEV_GROUP}"
  fi

  if [[ -d "/home/${user}" ]]; then
    owner="$(stat -c '%U' "/home/${user}")"
    perms="$(stat -c '%a' "/home/${user}")"
    if [[ "$owner" == "$user" && "$perms" == "700" ]]; then
      pass "Home directory /home/${user} is private (owner=${owner}, mode=${perms})"
    else
      fail "Home directory /home/${user} expected owner=${user} and mode=700, got owner=${owner} mode=${perms}"
    fi
  else
    fail "Home directory /home/${user} is missing"
  fi
done

if [[ -d "$TEAM_BIN" && -d "$TEAM_SHARED" && -f "$TEAM_DONE_LOG" ]]; then
  pass "Team workspace exists under ${TEAM_ROOT}"
else
  fail "Team workspace files are incomplete under ${TEAM_ROOT}"
fi

if [[ "$(stat -c '%a' "$TEAM_SHARED" 2>/dev/null || true)" == "3770" ]]; then
  pass "${TEAM_SHARED} has setgid + sticky bit (mode 3770)"
else
  fail "${TEAM_SHARED} is expected to have mode 3770"
fi

if runuser -u dev2 -- test -x /home/dev1 2>/dev/null; then
  fail "dev2 should not be able to traverse /home/dev1"
else
  pass "Private home directories block lateral access"
fi

if runuser -u dev1 -- "${TEAM_BIN}/team-env-check" >/dev/null 2>&1; then
  pass "Team members can execute shared scripts from ${TEAM_BIN}"
else
  fail "dev1 could not execute ${TEAM_BIN}/team-env-check"
fi

outsider=""
if id gsx >/dev/null 2>&1 && ! check_user_in_group gsx; then
  outsider="gsx"
elif id nobody >/dev/null 2>&1; then
  outsider="nobody"
fi
if [[ -n "$outsider" ]]; then
  if runuser -u "$outsider" -- "${TEAM_BIN}/team-env-check" >/dev/null 2>&1; then
    fail "Non-team user ${outsider} should not execute ${TEAM_BIN}/team-env-check"
  else
    pass "Non-team user ${outsider} is blocked from team bin"
  fi
else
  skip "No suitable outsider account found for negative execution test"
fi

testfile="${TEAM_SHARED}/week4-dev1-$$.txt"
if runuser -u dev1 -- bash -lc "umask 0007; printf 'week4 shared file\n' > '${testfile}'"; then
  if [[ "$(stat -c '%G' "$testfile")" == "$DEV_GROUP" ]]; then
    pass "Files created in ${TEAM_SHARED} inherit group ${DEV_GROUP}"
  else
    fail "Shared file did not inherit group ${DEV_GROUP}"
  fi
else
  fail "dev1 could not create a file in ${TEAM_SHARED}"
fi

if runuser -u dev2 -- test -r "$testfile" 2>/dev/null; then
  pass "Other team members can read shared files"
else
  fail "dev2 could not read shared file created by dev1"
fi

if runuser -u dev2 -- rm -f "$testfile" >/dev/null 2>&1; then
  fail "Sticky bit is not protecting ${TEAM_SHARED}; dev2 removed dev1's file"
else
  pass "Sticky bit prevents dev2 from deleting dev1's file"
fi
runuser -u dev1 -- rm -f "$testfile" >/dev/null 2>&1 || true

if runuser -u dev2 -- tail -n 1 "$TEAM_DONE_LOG" >/dev/null 2>&1; then
  pass "Team members can read ${TEAM_DONE_LOG}"
else
  fail "dev2 could not read ${TEAM_DONE_LOG}"
fi

marker="week4-verify-$$"
if runuser -u dev2 -- bash -lc "printf '%s\n' '${marker}' >> '${TEAM_DONE_LOG}'" >/dev/null 2>&1; then
  fail "dev2 should not be able to append to ${TEAM_DONE_LOG}"
  sed -i "\|${marker}|d" "$TEAM_DONE_LOG" || true
else
  pass "Only ${PRIMARY_WRITER} can append to ${TEAM_DONE_LOG}"
fi

if runuser -u "$PRIMARY_WRITER" -- bash -lc "printf '%s\n' '${marker}' >> '${TEAM_DONE_LOG}'"; then
  if tail -n 1 "$TEAM_DONE_LOG" | grep -Fxq "$marker"; then
    pass "${PRIMARY_WRITER} can append to ${TEAM_DONE_LOG}"
  else
    fail "${PRIMARY_WRITER} append test did not persist"
  fi
  sed -i '$d' "$TEAM_DONE_LOG" || true
else
  fail "${PRIMARY_WRITER} could not append to ${TEAM_DONE_LOG}"
fi

path_check="$(run_as_login dev4 'printf %s "$PATH"' 2>/dev/null || true)"
case ":${path_check}:" in
  *:/home/greendevcorp/bin:*)
    pass "Login shells inherit /home/greendevcorp/bin in PATH"
    ;;
  *)
    fail "Login PATH does not contain /home/greendevcorp/bin"
    ;;
esac

if runuser -l dev4 -c "bash -lic 'alias donelog >/dev/null 2>&1'" >/dev/null 2>&1; then
  pass "Interactive login shells inherit team aliases from /etc/profile.d"
else
  fail "Interactive login shell did not expose the donelog alias"
fi

nofile_soft_expected="$(limit_from_conf nofile soft)"
nofile_hard_expected="$(limit_from_conf nofile hard)"
nproc_soft_expected="$(limit_from_conf nproc soft)"
nproc_hard_expected="$(limit_from_conf nproc hard)"
as_soft_expected="$(limit_from_conf as soft)"
as_hard_expected="$(limit_from_conf as hard)"
cpu_soft_expected="$(limit_from_conf cpu soft)"
cpu_hard_expected="$(limit_from_conf cpu hard)"

actual_limits="$(run_as_login dev1 'printf "nofile_soft=%s\nnofile_hard=%s\nnproc_soft=%s\nnproc_hard=%s\nas_soft=%s\nas_hard=%s\ncpu_soft=%s\ncpu_hard=%s\n" "$(ulimit -Sn)" "$(ulimit -Hn)" "$(ulimit -Su)" "$(ulimit -Hu)" "$(ulimit -Sv)" "$(ulimit -Hv)" "$(ulimit -St)" "$(ulimit -Ht)"' 2>/dev/null || true)"
echo
echo "=== Inherited PAM limits for dev1 ==="
echo "$actual_limits"

echo "$actual_limits" | grep -Fxq "nofile_soft=${nofile_soft_expected}" && pass "nofile soft limit inherited from PAM" || fail "nofile soft limit mismatch"
echo "$actual_limits" | grep -Fxq "nofile_hard=${nofile_hard_expected}" && pass "nofile hard limit inherited from PAM" || fail "nofile hard limit mismatch"
echo "$actual_limits" | grep -Fxq "nproc_soft=${nproc_soft_expected}" && pass "nproc soft limit inherited from PAM" || fail "nproc soft limit mismatch"
echo "$actual_limits" | grep -Fxq "nproc_hard=${nproc_hard_expected}" && pass "nproc hard limit inherited from PAM" || fail "nproc hard limit mismatch"
echo "$actual_limits" | grep -Fxq "as_soft=${as_soft_expected}" && pass "address-space soft limit inherited from PAM" || fail "address-space soft limit mismatch"
echo "$actual_limits" | grep -Fxq "as_hard=${as_hard_expected}" && pass "address-space hard limit inherited from PAM" || fail "address-space hard limit mismatch"

expected_cpu_soft_seconds=$(( cpu_soft_expected * 60 ))
expected_cpu_hard_seconds=$(( cpu_hard_expected * 60 ))
echo "$actual_limits" | grep -Fxq "cpu_soft=${expected_cpu_soft_seconds}" && pass "CPU soft limit inherited from PAM" || fail "CPU soft limit mismatch"
echo "$actual_limits" | grep -Fxq "cpu_hard=${expected_cpu_hard_seconds}" && pass "CPU hard limit inherited from PAM" || fail "CPU hard limit mismatch"

nofile_probe_rc=0
runuser -l dev1 -c 'bash -lc '"'"'
  limit="$(ulimit -Sn)"
  [[ "$limit" == "unlimited" ]] && exit 99
  (( limit > 512 )) && exit 98
  i=10
  while (( i < limit + 32 )); do
    eval "exec ${i}</dev/null" || exit 42
    i=$((i + 1))
  done
  exit 0
'"'"'' >/dev/null 2>&1 || nofile_probe_rc=$?

case "$nofile_probe_rc" in
  42) pass "Open-file limit is actively enforced for login shells" ;;
  98) skip "nofile value is too high for quick active probe; inherited value check already passed" ;;
  99) fail "nofile is unlimited; PAM limit was not enforced" ;;
  0)  fail "Open-file probe did not hit the configured limit" ;;
  *)  fail "Open-file probe exited unexpectedly with status ${nofile_probe_rc}" ;;
esac

echo
echo "Summary: PASS=${pass_count} FAIL=${fail_count} SKIP=${skip_count}"
if (( fail_count > 0 )); then
  exit 1
fi
