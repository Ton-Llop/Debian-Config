# Week 3 — Process Management & Resource Control

Week 3 focuses on **debugging a slow server**, understanding **Linux processes + signals**, and enforcing **resource limits** so one workload cannot starve the whole machine.

## Deliverables mapping (Week 3)

### Part A — Process Inspection & Diagnostics

Diagnostics script (top consumers + tree + metrics):
- `opt/10-report-top-consumers.sh`

Optional scheduling (systemd):
- `etc/systemd/system/report-top.service`
- `etc/systemd/system/report-top.timer`

Generated evidence logs:
- `/srv/gsx-admin/logs/top-report/top-report-<timestamp>.log`

### Part B — Signals & Process Control

Workload + signal handling demo:
- `opt/11-workload-signals.sh`

Workload as a supervised systemd service:
- `etc/systemd/system/gsx-workload.service`

### Part C — Resource Limits

Setup (PAM limits + systemd cgroup limits):
- `opt/12-resource-limits-setup.sh`

Verification:
- `opt/13-verify-resource-limits.sh`
- `opt/14-ulimit-demo.sh`

### Part D — Documentation

Process concepts:
- `docs/Week3/ProcessConcepts.md`

Signals + process control:
- `docs/Week3/SignalsProcessControl.md`

Resource limits:
- `docs/Week3/ResourceLimits.md`

Monitoring checklist + troubleshooting:
- `docs/Runbooks/monitoring-checklist.md`
- `docs/Runbooks/troubleshoot-slow-server.md`
- `docs/Runbooks/troubleshoot-high-cpu.md`

Performance baseline:
- `docs/Week3/PerformanceBaseline.md`

Assignment questions (explicit answers):
- `docs/Week3/AssignmentQuestions.md`

---

## Quick demo commands (copy/paste)

### 1) Generate a diagnostics report now

```bash
sudo bash /home/gsx/gsx-admin/opt/10-report-top-consumers.sh
ls -lah /srv/gsx-admin/logs/top-report/
tail -n 60 /srv/gsx-admin/logs/top-report/top-report-*.log
```

### 2) Start workload manager manually and send signals

Terminal A:

```bash
bash /home/gsx/gsx-admin/opt/11-workload-signals.sh --workers 4 --nice 10
```

Terminal B:

```bash
pid=$(cat /tmp/gsx-workload-manager.pid)
kill -USR1 "$pid"   # status snapshot
kill -USR2 "$pid"   # pause/resume workers
kill -HUP  "$pid"   # reload config
kill -TERM "$pid"   # graceful shutdown
```

### 3) Run workload as a systemd service (with limits)

```bash
sudo systemctl enable --now gsx-workload.service
sudo systemctl status gsx-workload.service --no-pager

# send signals to the *main* process of the unit
sudo systemctl kill --kill-who=main -s SIGUSR1 gsx-workload.service
sudo systemctl kill --kill-who=main -s SIGUSR2 gsx-workload.service
sudo systemctl kill --kill-who=main -s SIGHUP  gsx-workload.service
```

### 4) Verify cgroup limits are enforced

```bash
sudo bash /home/gsx/gsx-admin/opt/13-verify-resource-limits.sh gsx-workload.service
```
