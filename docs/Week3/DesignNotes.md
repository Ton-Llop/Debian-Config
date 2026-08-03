# DesignNotes (Week 3)

This document explains **why** Week 3 is implemented the way it is, and includes the required Q&A.

---

## 1) Goals and constraints

Week 3 asks us to:
- diagnose “the server feels slow”
- demonstrate process control (signals, pause/resume, graceful shutdown)
- enforce resource limits (CPU/memory) using **cgroups** (systemd)
- document normal vs abnormal (baseline) + runbooks

Constraints we assumed:
- Debian base system
- prefer **standard tools** (ps/proc/systemd) and `apt`-available utilities
- keep paths stable under `/srv/gsx-admin` (shared admin tree)

---

## 2) Why a report script instead of “just use top”?

We created `opt/10-report-top-consumers.sh` to generate a timestamped report because:

- **Repeatability**: the report collects the same signals every time, in the same order.
- **Evidence**: output is saved under `/srv/gsx-admin/logs/top-report/` so we can review it later.
- **Explanation-friendly**: you can open one file and explain what it shows.
- **Operations thinking**: “slow server” diagnosis is a checklist, not a guess.

The report includes:
- top CPU / top memory process lists
- process tree (`pstree` / `ps --forest`) to catch “one parent spawning many workers”
- `/proc` snapshots for selected PIDs (state, limits, I/O counters)

Trade-off:
- tools like `htop` are great interactively, but their output is not ideal for automation.
  We rely on `ps` + `/proc` as the canonical data sources.

---

## 3) Why the workload manager handles signals itself

We needed a *controlled* way to demonstrate:
- background jobs
- signal handling (`SIGINT`, `SIGUSR1`, `SIGUSR2`)
- graceful shutdown vs force kill

`opt/11-workload-signals.sh` spawns CPU workers (`yes`) because:
- deterministic CPU load
- available everywhere
- easy to show effect of `nice`, STOP/CONT, and termination

The manager process implements:
- `SIGUSR1` → status dump
- `SIGUSR2` → pause/resume (STOP/CONT)
- `SIGTERM`/`SIGINT` → graceful shutdown path (TERM workers, then KILL if needed)

This makes the difference between “polite shutdown” and “hard kill” very clear.

---

## 4) Why we use systemd cgroups for limits

We enforce limits at the **service boundary** with systemd:

- `CPUQuota` / `MemoryMax` / `TasksMax` are kernel-enforced via cgroups
- limits follow the service even if it forks children (the whole cgroup is limited)
- evidence is inspectable using `systemctl show` and `/sys/fs/cgroup/...` control files

This is stronger than “renice” alone:
- `nice` changes priority but does not cap usage
- cgroups actually prevent one service from monopolizing resources

Implementation:
- `etc/systemd/system/gsx-workload.service` includes the cgroup limits
- `opt/12-resource-limits-setup.sh` applies the configuration and mirrors it into the repo
- `opt/13-verify-resource-limits.sh` prints the exact evidence for evaluation

---

## 5) Why we include per-user PAM limits too

Week 3 focuses on *process management*, and per-user `ulimit` limits are a standard sysadmin control:

- protects the system from accidental “too many files” or process explosions
- applies to login sessions (PAM), which matches how humans use the machine

We limit the `@gsx-admin` group in `/etc/security/limits.conf` and ensure PAM loads `pam_limits.so`.

We also include `opt/14-ulimit-demo.sh` to show a testable, deterministic “this fails without limits” style demo.

---

## 6) Required questions (explicit answers)

### Q1) How is killing a process with SIGTERM different from SIGKILL? When would you use each?
- **SIGTERM** (15): *request* termination.
  - default action is to terminate, **but the process can catch it** and run cleanup.
  - Use SIGTERM when you want a **graceful shutdown** (flush logs, close sockets, write state, release locks).
  - This is what `systemctl stop` normally sends (unless configured otherwise).
- **SIGKILL** (9): **immediate kill**, cannot be caught/ignored/handled.
  - kernel removes the process right away.
  - Use SIGKILL only when the process is **stuck**, not responding, or ignoring SIGTERM (e.g., deadlock, stuck in uninterruptible sleep, broken shutdown).

Where SIGUSR1 / SIGUSR2 fit:
- **SIGUSR1/SIGUSR2** are “application-defined” signals.
- In our workload demo:
  - `SIGUSR1` prints status (PIDs + quick resource snapshot)
  - `SIGUSR2` toggles pause/resume via STOP/CONT
- In real services they are often used for “reload config”, “rotate logs”, “dump stats”, etc.

### Q2) If your service receives a signal, how should it respond? Should it save state before exiting?
Best practice response (for SIGTERM/SIGINT):
1. **Stop accepting new work** (close listeners / stop scheduling new jobs).
2. **Finish or checkpoint in-flight work** if possible (bounded time).
3. **Flush/close**: logs, files, sockets; remove PID files; release locks.
4. Exit with a sensible code (0 for clean stop).

Should it save state?
- **Yes** if the service maintains any state that matters after restart:
  - queued jobs, partially processed tasks, last successful checkpoint, counters you care about, etc.
- **Maybe not** if the service is:
  - stateless, idempotent, or it can recompute safely
  - a oneshot job where rerun is harmless

Systemd integration:
- `TimeoutStopSec=` defines how long systemd will wait for graceful exit.
- After timeout, systemd may escalate (depending on KillMode/KillSignal).
- So you should implement graceful shutdown, but keep it **bounded**.

### Q3) How do you verify that a resource limit is actually working? Can you create a test that would fail without the limit?
Verification has two layers:

**(A) Configuration evidence**
- Confirm systemd properties:
  ```bash
  systemctl show gsx-workload.service -p CPUQuota -p MemoryMax -p TasksMax -p ControlGroup
  ```
- Confirm kernel control files (cgroup v2):
  ```bash
  CG=$(systemctl show gsx-workload.service -p ControlGroup --value)
  sudo cat /sys/fs/cgroup${CG}/cpu.max
  sudo cat /sys/fs/cgroup${CG}/memory.max
  sudo cat /sys/fs/cgroup${CG}/pids.max
  ```

**(B) Behavioral evidence (a test that would “fail” without the limit)**

CPUQuota test (clear effect):
- Start workload with many workers; without a quota it would consume ~100% of a core (or more).
- With `CPUQuota=25%`, the service’s cgroup should cap CPU time.
- Evidence:
  ```bash
  systemd-cgtop -b -n 3
  ps -o pid,pcpu,cmd -C yes | head
  ```
  You should observe the *unit* is limited relative to baseline.

MemoryMax test (hard cap):
- Run a memory-hog process inside the service (or a temporary systemd scope) that would exceed the cap.
- With the cap, it gets OOM-killed inside the cgroup; without the cap, it would consume large memory and pressure the system.

Example scope test (safe, bounded):
```bash
sudo systemd-run --unit=gsx-memtest -p MemoryMax=50M --pty   python3 -c 'a=" "*(200*1024*1024); print("allocated"); import time; time.sleep(5)'
```
Expected: the process should be killed when it exceeds the memory cap.

### Q4) If a developer’s job is using 90% CPU, is that a problem? How do you decide?
Not automatically. “90% CPU” is a symptom, not a diagnosis.

How we decide:
1. **Context**: is it expected (compile/test) or unexpected (runaway loop)?
2. **Impact**:
   - are other services suffering latency?
   - do users report slowness?
   - are systemd units restarting / timing out?
3. **Capacity**:
   - compare load average to CPU cores (`uptime`)
   - check run queue and steal/iowait (`vmstat`, `top`)
4. **Resource contention**:
   - memory pressure / swap?
   - I/O wait high?
5. **Baseline comparison**:
   - is this outside our “normal” snapshot?

If impact is acceptable:
- it may be fine (server doing work is normal)
- consider lowering priority with `nice`/`renice` for fairness

If impact is not acceptable:
- limit the job:
  - run it in a systemd scope with `CPUQuota`, or
  - keep it inside a cgroup-limited service
- or schedule it off-peak
- or investigate for bugs (infinite loop, fork storm, etc.)

Runbook references:
- `docs/Runbooks/troubleshoot-high-cpu.md`
- `docs/Runbooks/troubleshoot-slow-server.md`
