# Troubleshooting — “The server feels slow. What do I check?”

Goal: identify whether slowness is caused by **CPU**, **memory**, **disk I/O**, **network**, or a **specific service/process**.

---

## 0) First: define the symptom

Ask:
- Is it the whole server (SSH lag, commands slow), or only one app (e.g., nginx)?
- When did it start? Is it constant or intermittent?
- Did anything change recently (deploy, backup run, apt upgrade)?

---

## 1) Quick triage (60 seconds)

```bash
date --iso-8601=seconds
uptime
free -h
df -h /
systemctl --failed --no-pager
```

Interpretation:
- High load avg + slow response ⇒ CPU or I/O bottleneck.
- Low available memory + growing swap ⇒ memory pressure.
- Disk nearly full ⇒ many operations will degrade (logs, writes, tmp).

---

## 2) Identify the top offenders (CPU + RAM)

```bash
ps -eo pid,ppid,pcpu,pmem,stat,comm --sort=-pcpu | head -n 15
ps -eo pid,ppid,pcpu,pmem,stat,comm --sort=-pmem | head -n 15
```

If interactive tools are available:
```bash
top
htop
```

Generate a full evidence report:
```bash
sudo bash /home/gsx/gsx-admin/opt/10-report-top-consumers.sh
```

---

## 3) Decide CPU-bound vs I/O-bound

### CPU-bound signals
- One/few processes at very high `%CPU`
- system remains responsive-ish but “busy”

Actions:
- check whether this workload is expected
- consider lowering priority:

```bash
sudo renice -n 10 -p <pid>
```

### I/O-bound signals
- High load avg but CPU is not fully utilized
- Many processes in state `D` (uninterruptible sleep)

Actions:

```bash
sudo iotop -o
```

If `iotop` is missing:
```bash
sudo apt-get update && sudo apt-get install -y iotop
```

---

## 4) Memory pressure / swapping

```bash
free -h
```

Red flags:
- swap usage increasing over time
- many processes with high RSS

Actions:
- identify the top memory process (see step 2)
- restart the leaking service (if safe)

---

## 5) Service-specific investigation

If the problem is a specific unit:

```bash
systemctl status <unit> --no-pager
journalctl -u <unit> -n 200 --no-pager -o short-iso
```

If nginx feels slow:
```bash
sudo nginx -t
```

---

## 6) Contain the blast radius (resource limits)

If a repeatable workload is starving the server, apply limits:
- prefer **systemd service limits** (CPUQuota/MemoryMax/TasksMax) for long-running tasks

Verify our demo limits on the workload service:
```bash
sudo bash /home/gsx/gsx-admin/opt/13-verify-resource-limits.sh gsx-workload.service
```

---

## 7) Escalation: stop the offender safely

Try graceful first:
```bash
kill -TERM <pid>
```

If it does not stop and the server is at risk:
```bash
kill -KILL <pid>
```

For systemd services, prefer:
```bash
sudo systemctl stop <unit>
```
