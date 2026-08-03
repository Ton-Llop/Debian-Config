# Runbook – Checking Service Logs

## Purpose

Provide a consistent method to inspect logs for systemd-managed services.

All services log to journald.

---

## 1. Quick Overview (Status + Recent Logs)

```bash
systemctl status <service-name> --no-pager
```

Displays:
- Current state
- Recent log entries
- Exit status

---

## 2. View Full Logs for a Service

```bash
journalctl -u <service-name>
```

---

## 3. View Last N Log Lines

```bash
journalctl -u <service-name> -n 100 --no-pager
```

---

## 4. View Logs Within a Time Window

Last hour:

```bash
journalctl -u <service-name> --since "1 hour ago"
```

Specific timeframe:

```bash
journalctl -u <service-name> --since "YYYY-MM-DD HH:MM" --until "YYYY-MM-DD HH:MM"
```

---

## 5. View Only Warnings and Errors

```bash
journalctl -u <service-name> -p warning..alert
```

---

## 6. Check System-Wide Errors

```bash
journalctl -p err..alert -n 100
```

---

## 7. Backup Service Logs

```bash
journalctl -u gsx-backup.service -n 120 --no-pager
```

Check execution result:

```bash
systemctl show gsx-backup.service -p Result -p ExecMainStatus
```

---

## 8. Check Journald Disk Usage

```bash
journalctl --disk-usage
```

---

## Notes

- Logs are persistent.
- Retention is bounded by journald configuration.
- Operational logs under `/srv/gsx-admin/logs` are rotated via logrotate.
- Always inspect logs before restarting a service.