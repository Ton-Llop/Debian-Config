# Troubleshooting — “A process is using 90% CPU. What do I do?”

High CPU is not automatically “bad”. The right response depends on whether:
- the workload is expected (backup, build, test)
- the server remains responsive
- SLAs/users are affected

---

## 1) Confirm the situation

```bash
uptime
ps -eo pid,ppid,pcpu,pmem,stat,comm,args --sort=-pcpu | head -n 15
```

Record:
- PID, command, owner (user)
- how long it has been running
- whether it is a service (systemd) or a user process

---

## 2) Is it expected?

Examples of expected spikes:
- `apt-get upgrade`
- compression/encryption during backup
- a build/test job

If it’s expected and the server is fine:
- do nothing, but keep an eye on it

If users complain about responsiveness:
- continue with containment steps below.

---

## 3) Identify if it’s CPU-bound or stuck in a loop

Check the process state and threads:
```bash
pid=<pid>
ps -o pid,ppid,stat,pcpu,pmem,etime,cmd -p "$pid"
cat /proc/$pid/status | sed -n '1,80p'
```

If it’s a service, check logs:
```bash
unit=<unit>
systemctl status "$unit" --no-pager
journalctl -u "$unit" -n 200 --no-pager -o short-iso
```

---

## 4) Contain impact without killing

### Option A — Lower priority (nice/renice)

```bash
sudo renice -n 10 -p <pid>
```

This keeps the job running, but lets interactive/admin work win.

### Option B — Temporarily pause

```bash
kill -STOP <pid>
sleep 5
kill -CONT <pid>
```

For our demo workload manager, use:
```bash
kill -USR2 $(cat /tmp/gsx-workload-manager.pid)
```

---

## 5) Apply hard limits (preferred for repeatable workloads)

If the process is part of a service, enforce cgroup limits via systemd.

Example (our demo):
- `gsx-workload.service` uses `CPUQuota`, `MemoryMax`, `TasksMax`.

Verify:
```bash
sudo bash /home/gsx/gsx-admin/opt/13-verify-resource-limits.sh gsx-workload.service
```

---

## 6) Stop safely (graceful → force)

Try graceful termination first:
```bash
kill -TERM <pid>
```

If it’s a systemd unit:
```bash
sudo systemctl stop <unit>
```

If it refuses to stop and is harming the server:
```bash
kill -KILL <pid>
```

For the demo workload:
```bash
kill -TERM $(cat /tmp/gsx-workload-manager.pid)
# or last resort
kill -KILL $(cat /tmp/gsx-workload-manager.pid)
```

---

## 7) Post-incident: prevent recurrence

Actions:
- move repeatable heavy jobs under systemd with cgroup limits
- add a timer/report to capture evidence (`report-top.timer`)
- update the baseline (`docs/Week3/PerformanceBaseline.md`)
