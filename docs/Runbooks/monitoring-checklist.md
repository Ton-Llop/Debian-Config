# Monitoring Checklist — What to check regularly

This checklist is meant to be run **daily (quick)** and **weekly (deeper)** to catch problems early.

---

## Daily (5–10 minutes)

### 1) Are any services failing?

```bash
systemctl --failed --no-pager
```

### 2) Are key services active?

```bash
systemctl is-active nginx.service
systemctl is-active gsx-workload.service || true
```

### 3) Are timers running and not stuck?

```bash
systemctl list-timers --all --no-pager | sed -n '1,120p'
systemctl status gsx-backup.timer --no-pager
systemctl status report-top.timer --no-pager || true
```

### 4) Any warnings/errors in the last 24 hours?

```bash
journalctl -p warning..alert --since "24 hours ago" --no-pager -n 200
```

### 5) Basic resource snapshot

```bash
uptime
free -h
df -h /

# quick top offenders
ps -eo pid,pcpu,pmem,comm --sort=-pcpu | head -n 10
ps -eo pid,pcpu,pmem,comm --sort=-pmem | head -n 10
```

---

## Weekly (15–30 minutes)

### 1) Evidence report (top consumers)

```bash
sudo bash /home/gsx/gsx-admin/opt/10-report-top-consumers.sh
ls -1t /srv/gsx-admin/logs/top-report/ | head
```

### 2) Log storage is bounded

```bash
journalctl --disk-usage
sudo logrotate -d /etc/logrotate.conf >/dev/null && echo "logrotate parse: OK"
```

### 3) Resource limits enforcement (cgroups)

```bash
sudo bash /home/gsx/gsx-admin/opt/13-verify-resource-limits.sh gsx-workload.service
```

### 4) Backup freshness (sanity)

```bash
systemctl status gsx-backup.service --no-pager
journalctl -u gsx-backup.service --since "7 days ago" --no-pager | tail -n 80
```

---

## If you find something suspicious

Use:
- `docs/Runbooks/troubleshoot-slow-server.md`
- `docs/Runbooks/troubleshoot-high-cpu.md`
