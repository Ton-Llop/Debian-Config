# Runbook – Restarting a Crashed Service

## Purpose

Provide a safe and repeatable procedure to diagnose and restart a systemd-managed service.

Applies to:
- nginx.service
- nginx_setup.service
- gsx-backup.service
- Any future systemd unit

---

## 1. Check Service Status

```bash
systemctl status <service-name> --no-pager
```

Look for:
- `Active: failed`
- Exit code
- Recent log entries
- Restart attempts

---

## 2. Inspect Recent Logs

```bash
journalctl -u <service-name> -n 100 --no-pager
```

Check for:
- Configuration errors
- Permission issues
- Missing files
- Port conflicts
- Resource exhaustion

---

## 3. Validate Configuration (If Applicable)

For Nginx:

```bash
nginx -t
```

Only restart if configuration test is successful.

---

## 4. Restart the Service

```bash
sudo systemctl restart <service-name>
```

Verify:

```bash
systemctl status <service-name>
```

Expected state:

```
Active: active (running)
```

---

## 5. If the Service Fails Again

Re-check logs:

```bash
journalctl -u <service-name> --since "5 minutes ago"
```

Investigate:
- Invalid configuration
- Dependency not running
- Incorrect permissions
- Missing environment file (e.g., `/etc/gsx-admin/backup.env`)
- Port already in use

---

## Notes

- Services configured with `Restart=on-failure` automatically attempt recovery.
- All restart attempts are logged in journald.
- Always use `systemctl`; do not kill processes manually.