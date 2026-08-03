# Week 2 — Logging & Observability

When services fail, diagnose “what happened” using logs and standard tooling. fileciteturn0file1

This repo uses a **systemd-first** approach:
- runtime and service logs go to **journald** (queried with `journalctl`)
- operational evidence logs are written under `/srv/gsx-admin/logs/` and rotated with **logrotate**

---

## 1) journald (persistent logs + retention)

Script:
- `opt/06-logging-observability-setup.sh`

Repo-backed file:
- `etc/systemd/journald.conf.d/gsx.conf`

Installed to:
- `/etc/systemd/journald.conf.d/gsx.conf`

What the config enforces:
- `Storage=persistent` → logs survive reboot (stored under `/var/log/journal/`).
- disk caps (`SystemMaxUse`, `SystemKeepFree`, `RuntimeMaxUse`) to prevent journal growth from filling the disk.
- time retention (`MaxRetentionSec=1month`) as a “soft bound” alongside size caps.

Validate:

```bash
ls -ld /var/log/journal || true
journalctl --disk-usage

# show effective config sources (best)
systemd-analyze cat-config systemd/journald.conf | sed -n '1,200p'
```

---

## 2) Querying service logs

Status + recent logs:

```bash
systemctl status nginx --no-pager
```

Last 120 lines for a unit:

```bash
journalctl -u nginx -n 120 --no-pager -o short-iso
```

Errors/warnings in last 24 hours:

```bash
journalctl -p warning..alert --since "24 hours ago" -n 200 --no-pager -o short-iso
```

Runbook:
- `docs/Runbooks/check-service-logs.md`

---

## 3) Operational logs under /srv + logrotate

We store “evidence logs” (script outputs, diagnostics, verification logs) under:
- `/srv/gsx-admin/logs/`

Those logs are rotated with logrotate:

Repo-backed file:
- `etc/logrotate.d/gsx-admin`

Installed to:
- `/etc/logrotate.d/gsx-admin`

Why `su root gsx-admin` exists in the logrotate rule
- `/srv/gsx-admin/logs` is **group-writable** (collaboration).
- logrotate runs as root but, by default, refuses to rotate logs in group-writable dirs unless you specify `su`.
- The rule also uses `create 0664 root gsx-admin` so new rotated logs stay group-readable.

Dry-run parse check:

```bash
sudo logrotate -d /etc/logrotate.conf >/dev/null && echo OK
```

---

## 4) Evidence generation (verification script)

Script:
- `opt/07-verify-logging.sh`

What it writes:
- An evidence file under `/srv/gsx-admin/logs/` named like `week2-logging-verify-<timestamp>.log`.

Run:

```bash
sudo bash opt/07-verify-logging.sh

# optionally specify which units to include
sudo bash opt/07-verify-logging.sh nginx nginx_setup.service gsx-backup.service
```

The evidence file includes:
- journald persistence + disk usage
- recent warnings/errors
- `systemctl status` + `journalctl` excerpts for key services
- logrotate rule content + parse check
