# Design Notes (Week 2)

This document captures the rationale and trade-offs behind the **Week 2** implementation:

- systemd service management (Nginx + custom task)
- logging/observability (journald + retention, evidence logs, logrotate)
- automated backups (systemd timer, optional encryption, verification)

Week 2 goals and deliverables are described in the assignment brief. fileciteturn0file1 fileciteturn0file0

---

## 1) Why systemd (services + timers) instead of manual commands / cron

### Why systemd for services
- **Reliability**: systemd can supervise long-lived daemons (like Nginx) and react to failures.
- **Discoverability**: `systemctl status …` provides health + recent logs in one place.
- **Standardization**: this is the default service manager on modern Debian.

### Why systemd timers instead of cron
- Timers integrate with the same operational tools (`systemctl`, `journalctl`).
- `Persistent=true` makes schedules resilient to downtime (a missed run is executed after boot).
- Timers are easy to inspect (`systemctl list-timers`) and easy to trigger manually.

Trade-off:
- cron is simpler for tiny tasks, but it’s harder to reason about in a systemd-centric stack and logs are less consistent unless you wire them explicitly.

---

## 2) What should happen if Nginx crashes at 3 AM?

Target behavior:
1. systemd detects the failure
2. Nginx is automatically restarted (bounded retry)
3. The incident is visible in logs so an admin can explain root cause later

Implementation:
- Nginx runs as `nginx.service`.
- A systemd drop-in sets `Restart=on-failure` with a short delay.
- Logs are available via `journalctl -u nginx`.

What we do **not** implement in Week 2:
- Alerting/notification (email/Slack/etc.). This is typically the next layer (monitoring/metrics). For the assignment scope, our focus is: *restart + diagnose from logs*.

---

## 3) How do we test that auto-restart works?

You can’t just “wait for a crash”, so we simulate a failure in a controlled way:

- kill the service’s main process (`systemctl kill -s SIGKILL nginx`)
- confirm it returns to `active (running)`
- inspect the restart event in `journalctl`

This is documented in: `docs/Week2/ServiceManagement.md`.

---

## 4) Observability decisions

### journald as the primary log store
- systemd units already log to journald without extra configuration.
- `journalctl` queries are powerful (by unit, time, priority, etc.).
- It avoids managing many ad-hoc log files for services.

### Bounded retention (prevent logs consuming the disk)
We configure journald for:
- persistent storage (across reboots)
- disk usage caps
- a time retention ceiling

This reduces the “silent disk fill” failure mode.

### Why logrotate for `/srv/gsx-admin/logs`
We still write evidence logs and verification logs to a normal directory so they can be:
- referenced easily in reports/demo
- copied off-host
- read by the admin group

Because that directory is group-writable, logrotate needs an explicit `su root <group>` directive.

---

## 5) Backup automation decisions

### Why a oneshot service + timer
- Backup is a **job**, not a daemon → `Type=oneshot` fits.
- systemd captures stdout/stderr to journald automatically.
- `systemctl show …` makes it easy to surface exit codes and timestamps.

### Why optional encryption
- Backups include SSH config and SSH key material (depending on included paths).
- Encrypting at rest reduces risk if the VM disk or backup artifacts are exposed.

### Why secrets are not committed
- A passphrase in Git defeats the point.
- We keep repo-backed config in `etc/` but store secrets as runtime-only state:
  - `/etc/gsx-admin/backup.env` with `0600 root:root`
- The repo contains only `backup.env.example`.

### Failure mode design
- If encryption cannot run non-interactively (no passphrase + no TTY), the backup script falls back to plaintext tar by default (`ENCRYPT_MODE=auto`).
- This avoids “backup timer always fails” in headless automation.

Trade-off:
- Plaintext backups are weaker security. In practice, set a passphrase so timers can encrypt consistently.

---

## 6) If backups fail silently, how do we know?

We use multiple layers:
- systemd timer/service status (`systemctl status gsx-backup.timer`)
- service Result/exit status (`systemctl show gsx-backup.service …`)
- journald logs (`journalctl -u gsx-backup.service`)
- evidence script output saved under `/srv/gsx-admin/logs/` (`opt/09-verify-backup.sh`)

This provides a paper trail even without external alerting.

---

## 7) How would we explain a failure using only logs?

Procedure:
1. Identify the unit (`nginx`, `nginx_setup.service`, `gsx-backup.service`).
2. Capture:
   - `systemctl status <unit> --no-pager`
   - `journalctl -u <unit> -n 200 --no-pager -o short-iso`
3. Extract the earliest error message and the cause chain (missing file, permission denied, config test failed, etc.).

Runbooks:
- `docs/Runbooks/check-service-logs.md`
- `docs/Runbooks/restart-service.md`
