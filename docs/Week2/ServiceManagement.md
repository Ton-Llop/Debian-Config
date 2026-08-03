# Week 2 — Service Management (systemd)

Goal: services should be **reliable**, **discoverable**, and **recoverable** using standard tools (`systemctl`, `journalctl`). fileciteturn0file1

This repo implements:
- Nginx managed by systemd (enabled at boot)
- Automatic restart policy for Nginx
- A custom systemd oneshot service + timer that periodically records a small “health snapshot” to journald

---

## 1) Nginx

### Installed and enabled

Script:
- `opt/05-nginx_setup.sh`

Runtime checks:

```bash
systemctl status nginx --no-pager
systemctl is-enabled nginx
curl -I http://127.0.0.1/
```

### Auto-restart on failure

File (repo-backed):
- `etc/systemd/system/nginx.service.d/override.conf`

Installed to:
- `/etc/systemd/system/nginx.service.d/override.conf`

Key directives:
- `Restart=on-failure` — systemd restarts nginx if it exits with a failure condition.
- `RestartSec=2s` — wait 2 seconds before restart.
- `StartLimit*` — protects the host from restart loops.

Reload + apply:

```bash
sudo systemctl daemon-reload
sudo systemctl restart nginx
```

### How to test that auto-restart actually works

In a VM/lab environment you can simulate a crash:

```bash
sudo systemctl status nginx --no-pager

# Simulate failure by killing the main process
sudo systemctl kill -s SIGKILL nginx

# Within a few seconds it should return to "active (running)"
sleep 3
sudo systemctl status nginx --no-pager
```

Inspect the restart event in logs:

```bash
journalctl -u nginx --since "5 minutes ago" --no-pager -o short-iso
```

---

## 2) Custom periodic task (nginx_setup.service + nginx_setup.timer)

Purpose:
- Demonstrate a **custom** systemd-managed task (oneshot).
- Produce predictable logs in journald for observability.

### Unit files

Repo-backed:
- `etc/systemd/system/nginx_setup.service`
- `etc/systemd/system/nginx_setup.timer`

Installed to:
- `/etc/systemd/system/nginx_setup.service`
- `/etc/systemd/system/nginx_setup.timer`

ExecStart target created by script 05:
- `/usr/local/bin/nginx_setup.sh`

### How it runs

Timer settings:
- runs 1 minute after boot (`OnBootSec=1min`)
- then every 5 minutes (`OnUnitActiveSec=5min`)
- persistent timers: if the VM was off, systemd can “catch up” once it boots (`Persistent=true`)

Check timer schedule:

```bash
systemctl list-timers --all | grep -E 'nginx_setup\.timer'
systemctl status nginx_setup.timer --no-pager
```

Force a run now:

```bash
sudo systemctl start nginx_setup.service
```

View output:

```bash
journalctl -u nginx_setup.service -n 50 --no-pager -o short-iso
```

---

## 3) Operational runbooks

- Restart a service: `docs/Runbooks/restart-service.md`
- Check logs: `docs/Runbooks/check-service-logs.md`
