# Week 3 — Process Inspection & Diagnostics

Goal: quickly answer **“what is running?”** and **“what is consuming resources?”** using standard tooling + the repo’s diagnostics script.

---

## 1) Standard tools (manual triage)

### “What is using CPU/memory right now?”

```bash
top
# or a single-shot view
top -b -n 1 | head -n 30
```

### “Give me the top offenders in one line per process”

Top CPU:
```bash
ps -eo pid,ppid,pcpu,pmem,vsz,rss,comm --sort=-pcpu | head -n 15
```

Top memory:
```bash
ps -eo pid,ppid,pcpu,pmem,vsz,rss,comm --sort=-pmem | head -n 15
```

### “What is the parent/child structure?”

```bash
pstree -p -A | head -n 80
ps -eo pid,ppid,cmd --forest | head -n 80
```

### “Is disk I/O the bottleneck?”

```bash
sudo iotop -o
```

If `iotop` is missing:
```bash
sudo apt-get update && sudo apt-get install -y iotop
```

---

## 2) Diagnostics script: report-top-consumers

Script:
- `opt/10-report-top-consumers.sh`

What it does:
- Captures **top CPU** and **top memory** processes (via `ps`).
- Captures `top` batch snapshot.
- Attempts to capture **htop batch snapshot** (if `htop` supports batch mode).
- Captures a small **I/O sample** via `iotop` (root only).
- Captures **process tree** via `pstree` (fallback to `ps` if missing).
- Writes a timestamped report to:
  - `/srv/gsx-admin/logs/top-report/top-report-<timestamp>.log`

It also tries to ensure required tools exist via **apt-only installs** (`htop`, `iotop`).

Run now:
```bash
sudo bash /home/gsx/gsx-admin/opt/10-report-top-consumers.sh
```

Inspect latest report:
```bash
ls -1t /srv/gsx-admin/logs/top-report/ | head
tail -n 80 /srv/gsx-admin/logs/top-report/top-report-*.log
```

---

## 3) Scheduling with systemd (optional)

Units:
- `etc/systemd/system/report-top.service`
- `etc/systemd/system/report-top.timer`

Enable:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now report-top.timer

systemctl list-timers --all | grep report-top || true
```

Trigger manually (without waiting for the calendar time):
```bash
sudo systemctl start report-top.service
sudo systemctl status report-top.service --no-pager
journalctl -u report-top.service -n 120 --no-pager
```

### Common gotcha: ExecStart path

The timer/service will only work if `ExecStart` points to the correct script path.

Recommended stable runtime path:
- `/srv/gsx-admin/opt/10-report-top-consumers.sh`

If `report-top.service` references a different filename, fix it and reload:
```bash
sudo systemctl edit --full report-top.service
sudo systemctl daemon-reload
sudo systemctl restart report-top.timer
```
