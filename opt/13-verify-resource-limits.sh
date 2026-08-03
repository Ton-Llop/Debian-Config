#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Week 3 (Part C) verification helper:
# - Prints systemd limit settings
# - Shows the service's cgroup + raw cgroup control files
# - Shows a monitoring snapshot (systemd-cgtop) if available

UNIT="${1:-gsx-workload.service}"

# IMPORTANT: `systemctl status` exits non-zero for *inactive/failed* units.
# We only want to fail when the unit is truly missing (LoadState=not-found).
LOAD_STATE="$(systemctl show "$UNIT" -p LoadState --value 2>/dev/null || true)"
if [[ -z "$LOAD_STATE" || "$LOAD_STATE" == "not-found" ]]; then
  echo "ERROR: unit not found: $UNIT" >&2
  echo "Hint: check /etc/systemd/system/$UNIT and run: sudo systemctl daemon-reload" >&2
  exit 1
fi

echo "=== systemctl show (limits + usage + cgroup) ==="
systemctl show "$UNIT" \
  -p Id -p ActiveState -p SubState \
  -p CPUAccounting -p MemoryAccounting -p TasksAccounting \
  -p CPUQuota -p CPUQuotaPerSecUSec -p CPUUsageNSec \
  -p MemoryMax -p MemoryHigh -p MemoryCurrent \
  -p TasksMax -p NTasks \
  -p ControlGroup \
  --no-pager

CG="$(systemctl show "$UNIT" -p ControlGroup --value)"
CGPATH="/sys/fs/cgroup${CG}"

echo
echo "=== cgroup evidence (raw files) ==="
echo "ControlGroup: $CG"
if [[ -d "$CGPATH" ]]; then
  echo "Path: $CGPATH"
  for f in cpu.max cpu.stat memory.max memory.current memory.stat pids.max pids.current; do
    if [[ -f "$CGPATH/$f" ]]; then
      echo
      echo "--- $f ---"
      sed -n '1,40p' "$CGPATH/$f"
    fi
  done
else
  echo "NOTE: $CGPATH not found. (Maybe cgroup v1, or permission restrictions.)"
fi

echo
echo "=== systemctl status (snippet) ==="
systemctl status "$UNIT" --no-pager | sed -n '1,140p' || true

echo
echo "=== monitoring snapshot ==="
if command -v systemd-cgtop >/dev/null 2>&1; then
  systemd-cgtop -b -n 1 | sed -n '1,90p' || true
else
  echo "systemd-cgtop not found (usually provided by systemd)."
fi

echo
echo "=== cgroup tree (systemd-cgls) ==="
if command -v systemd-cgls >/dev/null 2>&1; then
  systemd-cgls "/system.slice/$UNIT" 2>/dev/null || systemd-cgls | sed -n '1,140p' || true
else
  echo "systemd-cgls not found (usually provided by systemd)."
fi

echo
echo "DONE."
