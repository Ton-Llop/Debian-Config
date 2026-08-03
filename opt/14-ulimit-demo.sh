#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Week 3 (Part C) ulimit demo (per-shell, non-root friendly)
#
# Demonstrates how `ulimit` affects the current shell/session by temporarily
# lowering the *soft* "open files" limit (nofile) and opening file descriptors
# until the limit is hit.

echo "=== Current ulimit (soft/hard) ==="
echo "nofile (soft): $(ulimit -Sn)"
echo "nofile (hard): $(ulimit -Hn)"
echo "nproc  (soft): $(ulimit -Su)"
echo "nproc  (hard): $(ulimit -Hu)"

ORIG_NOFILE="$(ulimit -Sn)"
TARGET_NOFILE="${1:-64}"

echo
echo "=== Setting temporary soft nofile limit to: $TARGET_NOFILE ==="
ulimit -Sn "$TARGET_NOFILE"

echo "Opening many file descriptors to /dev/null until it fails..."

fds=()
opened=0
for i in $(seq 1 500); do
  if exec {fd}>/dev/null 2>/dev/null; then
    fds+=("$fd")
    opened=$((opened+1))
  else
    echo "Stopped at i=$i (opened=$opened). Expected once you hit the nofile limit."
    break
  fi
done

echo
echo "=== Cleaning up (closing FDs) ==="
for fd in "${fds[@]}"; do
  eval "exec ${fd}>&-" || true
done

echo "Restoring original soft nofile limit: $ORIG_NOFILE"
ulimit -Sn "$ORIG_NOFILE" || true

echo
echo "DONE."
