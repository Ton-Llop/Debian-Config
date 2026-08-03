#!/usr/bin/env bash
# Produce a diagnostics report + deploy only the report-top artifacts (script + report-top.* units).
# Additionally: attempt to install/upgrade htop and iotop automatically via apt so the report can capture them.
set -euo pipefail
IFS=$'\n\t'

REPO_ROOT="${REPO_ROOT:-/home/gsx/gsx-admin}"        # your git repo root (source)
OUT_DIR="${OUT_DIR:-/srv/gsx-admin/logs/top-report}"            # where reports go
ADMIN_ROOT="${ADMIN_ROOT:-/srv/gsx-admin}"          # runtime admin tree where we place script & admin copy of units
SYSTEMD_SRC_DIR="${SYSTEMD_SRC_DIR:-${REPO_ROOT}/etc/systemd}" # units in repo (accepts etc/systemd or etc/systemd/system)
SYSTEMD_DEST_DIR="${SYSTEMD_DEST_DIR:-/etc/systemd/system}"    # system-wide units target
ADMIN_SYSTEMD_DIR="${ADMIN_ROOT}/etc/systemd/system"           # where we mirror units inside ADMIN_ROOT
ADMIN_OPT_DIR="${ADMIN_ROOT}/opt"                              # where we place runtime scripts inside ADMIN_ROOT

# Only deploy unit files that match this basename (so we don't deploy other unrelated units)
UNIT_BASENAME_PATTERN="${UNIT_BASENAME_PATTERN:-report-top}"  # e.g. report-top.service, report-top.timer

# Ownership
MIRROR_OWNER="${MIRROR_OWNER:-gsx:gsx}"

# Use rsync when available for file copying (no --delete here)
USE_RSYNC=1

# Helper: use sudo when not root
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
else
  SUDO=""
fi

TIMESTAMP="$(date --iso-8601=seconds)"

# Ensure output and admin dirs exist (try without sudo, fallback to sudo)
mkdir -p "$OUT_DIR" 2>/dev/null || $SUDO mkdir -p "$OUT_DIR"
$SUDO mkdir -p "$ADMIN_OPT_DIR" "$ADMIN_SYSTEMD_DIR"

# ----------------------------
# apt-only package helpers
# ----------------------------
apt_install_packages() {
  # args: package...
  local pkgs=("$@")
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "apt-get not found on this host; skipping automatic apt install."
    return 2
  fi

  echo "Attempting apt-get update and install for: ${pkgs[*]}"
  # update (best-effort)
  $SUDO apt-get update -y || echo "apt-get update failed (continuing)..."
  # install non-interactively
  if ! $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"; then
    echo "Warning: apt-get install failed for packages: ${pkgs[*]}. You may need to install them manually."
    return 1
  fi
  return 0
}

ensure_htop_iotop() {
  # Attempt to install/upgrade htop and iotop via apt. Non-fatal if it fails.
  echo "=== Ensuring htop and iotop are installed/up-to-date via apt ==="
  local to_install=()
  to_install+=("htop" "iotop")

  # Quick pre-check: if apt isn't present, skip and warn
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "apt-get not available on this system; automatic installation skipped."
    return 2
  fi

  # Try apt install (best-effort). If it fails, continue without stopping the whole script.
  if ! apt_install_packages "${to_install[@]}"; then
    echo "Note: automatic apt install/upgrade returned a non-zero status; continuing without guaranteed htop/iotop."
    # on Debian/RHEL differences: the script won't try to enable EPEL automatically
    return 1
  fi

  echo "Re-checking availability after apt attempt..."
  command -v htop >/dev/null 2>&1 && echo " - htop: available"
  command -v iotop >/dev/null 2>&1 && echo " - iotop: available"
  return 0
}

# ----------------------------
# Report generation function
# ----------------------------
generate_report() {
  local out_file="${OUT_DIR}/top-report-${TIMESTAMP}.log"
  {
    echo "==== Top resource consumers report ===="
    echo "Timestamp: $TIMESTAMP"
    echo "Host: $(hostname -f) | Uptime: $(uptime -p 2>/dev/null || true)"
    echo "Kernel: $(uname -r)"
    if command -v lsb_release >/dev/null 2>&1; then
      echo "OS: $(lsb_release -ds 2>/dev/null || true)"
    else
      awk -F= '/^PRETTY_NAME=/{gsub(/"/,"",$2); print "OS: "$2; exit}' /etc/os-release 2>/dev/null || true
    fi
    echo

    echo "---- Top 10 by CPU (%) (ps) ----"
    ps -eo pid,ppid,pcpu,pmem,vsz,rss,comm --sort=-pcpu | head -n 11 || true
    echo

    echo "---- Top 10 by Memory (%) (ps) ----"
    ps -eo pid,ppid,pcpu,pmem,vsz,rss,comm --sort=-pmem | head -n 11 || true
    echo

    if command -v top >/dev/null 2>&1; then
      echo "---- top (batch snapshot) ----"
      top -b -n1 | sed -n '1,20p' || true
      echo
      echo "---- top: top processes ----"
      top -b -n1 | sed -n '7,40p' | head -n 20 || true
      echo
    else
      echo "top: not installed"
      echo
    fi

    echo "---- htop snapshot ----"
    if command -v htop >/dev/null 2>&1; then
      # Check if htop supports batch mode (-b present in help for v3+)
      if htop --help 2>&1 | grep -q -- "-b"; then
        htop -b -n 1 | head -n 30 || true
      else
        echo "htop installed but no batch mode (old version) — skipping automated capture. Run 'htop' interactively if needed."
      fi
    else
      echo "htop not installed."
    fi
    echo

    echo "---- I/O (iotop) sample ----"
    if command -v iotop >/dev/null 2>&1; then
      if [ "$(id -u)" -eq 0 ]; then
        iotop -b -n 2 -k | sed -n '1,40p' || true
      else
        echo "iotop: requires root to capture I/O. Re-run as sudo to include iotop info."
      fi
    else
      echo "iotop: not installed. (Optional) sudo apt install -y iotop"
    fi
    echo

    echo "---- Process tree (pstree or ps fallback) ----"
    if command -v pstree >/dev/null 2>&1; then
      pstree -p -A | sed -n '1,120p' || true
    else
      # fallback: list top-level processes with child counts
      ps -eo pid,ppid,comm | awk 'NR==1{print;next} {child[$2]++; parent[$1]=$0} END{for (p in parent) print parent[p] " children=" child[p]}' | head -n 40 || true
    fi
    echo

    echo "---- Helpful manual commands (for a suspicious PID) ----"
    cat <<'EOF'
# Example commands to further inspect a suspicious PID (e.g., 1234):
#   pstree -sp 1234
#   ps -o pid,ppid,uid,user,pcpu,pmem,vsz,rss,stat,cmd -p 1234
#   sudo ls -l /proc/1234/fd
#   sudo lsof -p 1234
#   sudo strace -p 1234   (careful: intrusive)
#   sudo cat /proc/1234/status
#   sudo pmap -x 1234
EOF
    echo
    echo "Report generated by: $0"
  } > "$out_file"

  echo "Saved report: $out_file"
  echo "$out_file"
}

# ----------------------------
# Copy helper (rsync preferred)
# ----------------------------
copy_file_preserve() {
  local src="$1"
  local dest="$2"
  if command -v rsync >/dev/null 2>&1 && [ "$USE_RSYNC" -eq 1 ]; then
    $SUDO rsync -a "$src" "$dest"
  else
    $SUDO cp -a "$src" "$dest"
  fi
}

# ----------------------------
# Deploy only the report-top artifacts (script + matching unit files)
# ----------------------------
deploy_report_top_artifacts() {
  echo "=== Deploying report-top artifacts ==="

  # 1) Copy the runtime script (this file) into ADMIN_OPT_DIR
  # Note: this relies on the script being executed from the repo's opt/ or similar location
  local script_src
  script_src="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  local script_dest="${ADMIN_OPT_DIR}/$(basename "${BASH_SOURCE[0]}")"

  echo "Copying script to admin opt: $script_src -> $script_dest"
  copy_file_preserve "$script_src" "$script_dest" || { echo "Failed to copy script"; return 1; }
  $SUDO chmod +x "$script_dest" || true

  if id -u "${MIRROR_OWNER%%:*}" >/dev/null 2>&1; then
    $SUDO chown "${MIRROR_OWNER}" "$script_dest" || true
  fi

  # 2) Find report-top unit files in repo
  local units=()
  # check SYSTEMD_SRC_DIR (e.g., /home/gsx/gsx-admin/etc/systemd or etc/systemd/system)
  if [ -d "$SYSTEMD_SRC_DIR" ]; then
    # look for files matching UNIT_BASENAME_PATTERN.*
    while IFS= read -r -d '' f; do units+=("$f"); done < <(find "$SYSTEMD_SRC_DIR" -maxdepth 3 -type f -name "${UNIT_BASENAME_PATTERN}.*" -print0 2>/dev/null || true)
  fi

  # If nothing found, try also /etc/systemd in repo
  local alt_dir="${REPO_ROOT}/etc/systemd/system"
  if [ ${#units[@]} -eq 0 ] && [ -d "$alt_dir" ]; then
    while IFS= read -r -d '' f; do units+=("$f"); done < <(find "$alt_dir" -maxdepth 2 -type f -name "${UNIT_BASENAME_PATTERN}.*" -print0 2>/dev/null || true)
  fi

  if [ ${#units[@]} -eq 0 ]; then
    echo "No report-top unit files found in repo (checked: $SYSTEMD_SRC_DIR and $alt_dir). Nothing to deploy."
    return 0
  fi

  echo "Units found to deploy:"
  for u in "${units[@]}"; do echo " - $u"; done

  # 3) Backup dir for overwritten systemd units
  local backup_dir="/srv/gsx-admin/backups/gsx-report-top-units-${TIMESTAMP}"
  $SUDO mkdir -p "$backup_dir"
  echo "Backups (if overwriting) will be stored at: $backup_dir"

  # Ensure admin systemd directory exists
  $SUDO mkdir -p "$ADMIN_SYSTEMD_DIR"

  for src in "${units[@]}"; do
    local unit_name
    unit_name="$(basename "$src")"
    local dest_admin="${ADMIN_SYSTEMD_DIR}/${unit_name}"
    local dest_system="${SYSTEMD_DEST_DIR}/${unit_name}"

    # copy into /srv admin tree
    echo "Copying to admin tree: $src -> $dest_admin"
    copy_file_preserve "$src" "$dest_admin" || { echo "Failed to copy to admin tree: $src"; continue; }
    if id -u "${MIRROR_OWNER%%:*}" >/dev/null 2>&1; then
      $SUDO chown "${MIRROR_OWNER}" "$dest_admin" || true
    fi

    # backup existing system unit if present
    if [ -f "$dest_system" ]; then
      echo "Backing up existing system unit: $dest_system -> $backup_dir/$unit_name"
      $SUDO cp -a "$dest_system" "$backup_dir/$unit_name" || echo "Warning: backup failed for $dest_system"
    fi

    # copy to system units dir
    echo "Deploying system unit: $src -> $dest_system"
    copy_file_preserve "$src" "$dest_system" || { echo "Failed to deploy unit to $dest_system"; continue; }
    $SUDO chmod 644 "$dest_system" || true
  done

  # reload systemd to pick up changes
  echo "Reloading systemd daemon..."
  $SUDO systemctl daemon-reload || echo "Warning: systemctl daemon-reload failed"

  echo "Deploy complete."
  return 0
}

main() {
  # Ensure htop and iotop are present or attempt to install them via apt
  ensure_htop_iotop || echo "Note: ensure_htop_iotop returned a non-zero status; continuing without guaranteed htop/iotop."

  # generate report
  local report_path
  report_path="$(generate_report)"

  # deploy only the report-top artifacts
  if ! deploy_report_top_artifacts; then
    echo "Warning: deploy_report_top_artifacts reported a failure. Check output above."
  fi

  # final message
  echo "Done. Report: $report_path"
  echo "Script copy: ${ADMIN_OPT_DIR}/$(basename "${BASH_SOURCE[0]}")"
  echo "Admin systemd dir: ${ADMIN_SYSTEMD_DIR}"
  echo "Systemd units deployed to: ${SYSTEMD_DEST_DIR}"
}

main "$@"