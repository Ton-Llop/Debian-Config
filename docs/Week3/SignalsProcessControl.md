# Week 3 — Signals & Process Control (demo + reasoning)

Week 3 requires a demonstration of:
- background workloads
- signal handling (`SIGINT`, `SIGUSR1`, `SIGUSR2`)
- graceful stop vs force-kill

We implement this with `yes` workers managed by a signal-aware supervisor script.

---

## 1) Workload manager script

Script:
- `opt/11-workload-signals.sh`

What it does:
- Spawns N background **CPU-load workers** using `yes`.
- Names worker processes `gsx-workload-yes` (so `killall` can target them easily).
- Installs signal handlers via `trap`:
  - `SIGINT` / `SIGTERM`: graceful shutdown (TERM → wait → KILL after timeout)
  - `SIGUSR1`: status dump (PIDs + `ps` + `pstree` snapshot)
  - `SIGUSR2`: toggle pause/resume (STOP/CONT)
  - `SIGHUP`: reload config file (`WORKERS`, `NICE`, `OUTPUT`)
- Writes a PID file (default): `/tmp/gsx-workload-manager.pid`
- Logs manager messages to: `/srv/gsx-admin/logs/workload/workload-manager.log`

---

## 2) Demo: run manually + send signals

### Terminal A: start workload

```bash
bash /home/gsx/gsx-admin/opt/11-workload-signals.sh --workers 4 --nice 10
```

Confirm workers exist:
```bash
ps -ef | grep gsx-workload-yes | grep -v grep
```

### Terminal B: send signals

```bash
pid=$(cat /tmp/gsx-workload-manager.pid)

# status snapshot
kill -USR1 "$pid"

# pause workers (STOP)
kill -USR2 "$pid"

# resume workers (CONT)
kill -USR2 "$pid"

# reload config (SIGHUP)
kill -HUP "$pid"

# graceful stop (TERM)
kill -TERM "$pid"
```

---

## 3) Graceful stop vs force kill (what changes)

### Graceful stop

Graceful means:
1. send `SIGTERM`
2. allow the manager to stop workers cleanly
3. clean PID file and exit

Command:
```bash
kill -TERM $(cat /tmp/gsx-workload-manager.pid)
```

Expected:
- workers disappear
- PID file removed
- log contains “Shutdown complete.”

### Force kill

Force kill means:
- send `SIGKILL` to the manager (no handler can run)

Command:
```bash
kill -KILL $(cat /tmp/gsx-workload-manager.pid)
```

Expected:
- manager dies immediately
- PID file may remain (stale)
- worker processes may keep running until killed separately

Clean up workers if needed:
```bash
sudo apt-get update && sudo apt-get install -y psmisc   # provides killall/pstree on Debian
killall -TERM gsx-workload-yes
killall -KILL gsx-workload-yes   # last resort
```

---

## 4) Process control extras: pause/resume and priority

### Pause/resume

Pause with `SIGSTOP` (via `SIGUSR2` handler):
- workers transition to state `T` (stopped)

Observe:
```bash
ps -o pid,stat,pcpu,pmem,comm -p $(pgrep -f gsx-workload-yes | tr '\n' ' ')
```

### Priority (nice)

Workers are started with a nice value (default `10`). Lower priority means:
- the system remains interactive even under CPU load

You can change nice via config reload (SIGHUP) or set it at start:
```bash
bash opt/11-workload-signals.sh --workers 6 --nice 15
```

---

## 5) Running the workload as a systemd service

Unit:
- `etc/systemd/system/gsx-workload.service`

Start/stop:
```bash
sudo systemctl enable --now gsx-workload.service
sudo systemctl status gsx-workload.service --no-pager

sudo systemctl stop gsx-workload.service
```

Send signals to the unit’s **main process**:
```bash
sudo systemctl kill --kill-who=main -s SIGUSR1 gsx-workload.service
sudo systemctl kill --kill-who=main -s SIGUSR2 gsx-workload.service
sudo systemctl kill --kill-who=main -s SIGHUP  gsx-workload.service
```

Force kill (last resort):
```bash
sudo systemctl kill -s SIGKILL gsx-workload.service
```
