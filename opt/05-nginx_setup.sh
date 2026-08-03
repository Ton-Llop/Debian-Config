#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Week 2: Nginx + custom service + timer (systemd) + Git Sync
# + Mirror /etc files into:
#   - repo:        /home/$user/gsx-admin/etc/...
#   - admin share: /srv/gsx-admin/etc/...
# -----------------------------

# --- Repo path ---
# If you pass an argument it uses that, otherwise uses current dir (pwd)
REPO_DIR="${1:-$(pwd)}"

# Detect repo owner to run git as that user
GIT_USER="$(stat -c '%U' "$REPO_DIR" 2>/dev/null || echo "gsx")"

# Admin shared directory (gsx-admin group directory)
ADMIN_DIR="/srv/gsx-admin"

CUSTOM_NAME="nginx_setup"

TASK_SCRIPT="/usr/local/bin/${CUSTOM_NAME}.sh"

SERVICE_FILE="/etc/systemd/system/${CUSTOM_NAME}.service"
TIMER_FILE="/etc/systemd/system/${CUSTOM_NAME}.timer"

NGINX_OVERRIDE_DIR="/etc/systemd/system/nginx.service.d"
NGINX_OVERRIDE_FILE="${NGINX_OVERRIDE_DIR}/override.conf"

# Timer config
ONBOOT="1min"
INTERVAL="5min"

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
  # If gsx-admin group doesn't exist, fall back to root:root
  local grp="gsx-admin"
  if ! getent group "$grp" >/dev/null 2>&1; then
    grp="root"
  fi

  install -D -m 0664 -o root -g "$grp" \
    "$src" "${ADMIN_DIR}${src}"
}

if [[ $EUID -ne 0 ]]; then
  fail "este script debe ejecutarse como root (usa sudo)."
fi

# Basic sanity: repo should exist
if [[ ! -d "$REPO_DIR" ]]; then
  fail "REPO_DIR no existe: $REPO_DIR"
fi

# Ensure admin shared dir exists
mkdir -p "$ADMIN_DIR"
# Make it group-collab friendly if gsx-admin exists
if getent group gsx-admin >/dev/null 2>&1; then
  chown root:gsx-admin "$ADMIN_DIR"
  chmod 2775 "$ADMIN_DIR"   # setgid so new files keep group gsx-admin
else
  chmod 0755 "$ADMIN_DIR"
fi

echo "[1/8] Actualizando e instalando Nginx..."
apt-get update -y
apt-get install -y nginx

echo "[2/8] Habilitando Nginx al arranque..."
systemctl enable --now nginx

echo "[3/8] Configurando auto-restart de Nginx (override)..."
mkdir -p "$NGINX_OVERRIDE_DIR"
cat > "$NGINX_OVERRIDE_FILE" <<'EOF'
[Service]
Restart=on-failure
RestartSec=2s
StartLimitIntervalSec=60
StartLimitBurst=5
EOF

echo "[4/8] Creando script de tarea custom en $TASK_SCRIPT..."
cat > "$TASK_SCRIPT" <<'EOF'
#!/bin/bash
set -euo pipefail
echo "=== GSX Week2 task: $(date -Is) ==="
echo "Hostname: $(hostname)"
echo "Nginx active: $(systemctl is-active nginx || true)"
echo "Nginx enabled: $(systemctl is-enabled nginx || true)"
echo "Uptime: $(uptime)"
EOF
chmod 0755 "$TASK_SCRIPT"

echo "[5/8] Creando systemd service y timer..."
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=GSX Week2 Custom Task (logs to journal)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${TASK_SCRIPT}
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes

[Install]
WantedBy=multi-user.target
EOF

cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Run GSX Week2 Custom Task every ${INTERVAL}

[Timer]
OnBootSec=${ONBOOT}
OnUnitActiveSec=${INTERVAL}
Unit=${CUSTOM_NAME}.service
Persistent=true

[Install]
WantedBy=timers.target
EOF

echo "[6/8] Mirroring edited /etc files into repo and admin share..."
# Mirror:
#  - /etc/systemd/system/nginx_setup.service
#  - /etc/systemd/system/nginx_setup.timer
#  - /etc/systemd/system/nginx.service.d/override.conf
mirror_etc_file "$SERVICE_FILE"
mirror_etc_file "$TIMER_FILE"
mirror_etc_file "$NGINX_OVERRIDE_FILE"

echo "[7/8] Sincronizando con GitHub (Usuario: $GIT_USER)..."
if [[ -d "$REPO_DIR/.git" ]]; then
  # Add the mirrored files using repo-relative paths
  REL_SERVICE="etc/systemd/system/${CUSTOM_NAME}.service"
  REL_TIMER="etc/systemd/system/${CUSTOM_NAME}.timer"
  REL_OVERRIDE="etc/systemd/system/nginx.service.d/override.conf"

  sudo -u "$GIT_USER" git -C "$REPO_DIR" add "$REL_SERVICE" "$REL_TIMER" "$REL_OVERRIDE"

  if ! sudo -u "$GIT_USER" git -C "$REPO_DIR" diff --cached --quiet; then
    sudo -u "$GIT_USER" git -C "$REPO_DIR" commit -m "Week2: mirror systemd units + nginx override ($(date +'%Y-%m-%d %H:%M'))"
    echo "Haciendo push a GitHub..."
    sudo -u "$GIT_USER" git -C "$REPO_DIR" push origin main || sudo -u "$GIT_USER" git -C "$REPO_DIR" push origin master
  else
    echo "No se detectaron cambios nuevos para comitear."
  fi
else
  echo "AVISO: No se encontró un repositorio Git en $REPO_DIR. Saltando commit."
fi

echo "[8/8] Finalizando: Recargando systemd y activando timer..."
systemctl daemon-reload
nginx -t
systemctl restart nginx
systemctl enable --now "${CUSTOM_NAME}.timer"

echo "---"
echo "PROCESO COMPLETADO EXITOSAMENTE."
echo
echo "Mirrors created:"
echo "  Repo:        ${REPO_DIR}/etc/systemd/system/..."
echo "  Admin share: ${ADMIN_DIR}/etc/systemd/system/..."
