# Runbook — Verifying systemd Timers

## Purpose

Confirm that scheduled tasks (timers) are enabled, running, and actually triggering their services.

Applies to:
- `nginx_setup.timer`
- `gsx-backup.timer`

---

## 1) List timers (next + last run)

```bash
systemctl list-timers --all
```

Filter a specific timer:

```bash
systemctl list-timers --all | grep -E 'nginx_setup\.timer|gsx-backup\.timer'
```

---

## 2) Check status of the timer unit

```bash
systemctl status <timer-name>.timer --no-pager
systemctl is-enabled <timer-name>.timer
systemctl is-active  <timer-name>.timer
```

---

## 3) Confirm the service ran (logs)

```bash
journalctl -u <timer-name>.service -n 100 --no-pager -o short-iso
```

For backup jobs, also check the last Result/exit code:

```bash
systemctl show gsx-backup.service -p Result -p ExecMainStatus -p ActiveEnterTimestamp -p ActiveExitTimestamp
```

---

## 4) Force-run the job now

Systemd timers trigger services; you can start the service directly:

```bash
sudo systemctl start nginx_setup.service
sudo systemctl start gsx-backup.service
```

Then re-check logs:

```bash
journalctl -u nginx_setup.service -n 60 --no-pager -o short-iso
journalctl -u gsx-backup.service -n 120 --no-pager -o short-iso
```

---

## Notes

- If the timer is enabled but not firing, check time settings and whether the system was asleep/off.
- `Persistent=true` means systemd will catch up after reboot for missed schedules.
