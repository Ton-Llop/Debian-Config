# Week 3 — Performance Baseline (normal vs abnormal)

The point of a baseline is to answer:

> “Is this server slow **today**, or is this just what it normally looks like?”

We define a baseline as a **repeatable snapshot** taken when the system is healthy.

---

## 1) Baseline capture (recommended procedure)

Take the baseline when:
- no intentional stress tests are running
- services are up (`nginx`, `gsx-backup.timer`, etc.)

Run:
```bash
date --iso-8601=seconds
uptime
free -h
df -h /

# save a report under /srv/gsx-admin/logs/top-report/
sudo bash /home/gsx/gsx-admin/opt/10-report-top-consumers.sh
```

Optional deeper signals (install if needed):
```bash
sudo apt-get update && sudo apt-get install -y sysstat
iostat -xz 1 3
```

---

## 2) Baseline table (fill this once)

Record your VM’s “healthy” ranges (idle/normal use).

| Metric | Normal (baseline) | Abnormal (investigate) | How to check |
|---|---|---|---|
| Load average (1m/5m/15m) | ____ / ____ / ____ | sustained > CPU cores | `uptime` |
| CPU idle / iowait | ____ / ____ | iowait high, idle low | `top`, `iostat` |
| Top CPU process | ____ | unexpected process dominates | report-top log |
| RAM used / available | ____ / ____ | free very low, swap climbing | `free -h` |
| Swap used | ____ | growing steadily | `free -h` |
| Disk usage (%) | ____ | > 80–90% | `df -h` |
| Journald disk usage | ____ | growing without bound | `journalctl --disk-usage` |
| Failed units | none | any failed | `systemctl --failed` |
| Timer health | backups + reports run | missed/failed timers | `systemctl list-timers` |

Attach evidence:
- the first generated `top-report-<timestamp>.log` under `/srv/gsx-admin/logs/top-report/`

---

## 3) “Normal vs abnormal” examples (how to reason)

### Load average

- **Normal**: brief spikes while apt runs or backups execute.
- **Abnormal**: load stays high for minutes with the server feeling laggy.

Interpretation:
- High load + high CPU usage ⇒ CPU contention.
- High load + high iowait / many `D` processes ⇒ disk bottleneck.

### CPU usage

- **Normal**: one process at 80–100% for a short build/test can be fine.
- **Abnormal**: sustained 90% by an unknown process, or system responsiveness degraded.

### Memory pressure

- **Normal**: cache/buffers fill RAM (Linux uses spare RAM for cache).
- **Abnormal**: swap usage grows continuously; many processes slow down (paging).

---

## 4) What we do when baseline is exceeded

Use these runbooks:
- `docs/Runbooks/troubleshoot-slow-server.md`
- `docs/Runbooks/troubleshoot-high-cpu.md`
