# Week 3 — Process Concepts (what we need to reason about)

This page explains the core **process concepts** used in Week 3: inspection, lifecycle, signals, job control, and priorities.

---

## 1) What a process is (and why it matters)

In Linux, a **process** is a running program instance with:
- a PID (process id)
- a parent PID (PPID)
- a memory map (code/heap/stack/shared libs)
- open file descriptors (FDs)
- scheduling state (running, sleeping, etc.)
- security context (UID/GID, capabilities)

The server “feels slow” when processes compete for resources:
- CPU (compute bound)
- RAM + swap (memory pressure)
- Disk I/O (iowait, slow reads/writes)
- Locks / contention (many threads)
- Network (timeouts, retransmits)

---

## 2) Process lifecycle: fork → exec → wait → exit

Typical lifecycle:
1. **fork()**: parent creates a child (initially a copy)
2. **exec()**: child replaces its memory with a new program
3. **wait()**: parent collects child exit status
4. **exit()**: child finishes

Why you care:
- Services often have a **main process** and **worker children**.
- If the parent dies without waiting, you can get zombies.

---

## 3) Process states (R, S, D, T, Z)

You’ll see these in `ps` / `top` / `htop`:

- **R**: running (actually executing on CPU)
- **S**: sleeping (waiting for an event; normal)
- **D**: uninterruptible sleep (usually blocked on I/O; suspicious if long)
- **T**: stopped (SIGSTOP / job control)
- **Z**: zombie (exited but not reaped; symptom of a bug)

Common diagnosis hints:
- High load with many **D** processes ⇒ disk I/O problem.
- High CPU with many **R** processes ⇒ CPU contention.
- Persistent **Z** processes ⇒ parent not collecting children.

---

## 4) Process trees, sessions, and job control

### Parent/child relationships

Use:
- `pstree -p -A`
- `ps -eo pid,ppid,cmd --forest`

Why:
- You can identify the “root” of a runaway process family.
- Killing the wrong PID can leave orphan workers.

### Process groups (PGID)

When you run a command in a shell, it typically belongs to a **process group**.
Signals can be sent to a PID or to a group.

### Foreground/background jobs

In a shell:
- run in background: `command &`
- list jobs: `jobs`
- bring to foreground: `fg %1`
- stop: `Ctrl+Z`

---

## 5) Signals (what they are, and why they’re not the same)

Signals are lightweight notifications sent to processes.

Key ones used in Week 3:

- **SIGTERM (15)**: “please exit” (graceful; can be handled)
- **SIGKILL (9)**: force kill (cannot be handled; last resort)
- **SIGINT (2)**: interactive interrupt (`Ctrl+C`)
- **SIGHUP (1)**: reload configuration (common daemon convention)
- **SIGSTOP / SIGCONT**: pause/resume (cannot be ignored)
- **SIGUSR1 / SIGUSR2**: app-defined behavior

Rule of thumb:
1. Try **SIGTERM** (or the service’s normal stop path).
2. If it won’t die and is harming the system, escalate to **SIGKILL**.

---

## 6) Priorities: nice / renice

Linux scheduling priority is influenced by **nice** values:
- lower nice ⇒ higher priority (e.g., `-5`)
- higher nice ⇒ lower priority (e.g., `+15`)

Commands:
```bash
nice -n 15 my_job
sudo renice -n 10 -p <pid>
```

Why:
- If a developer workload is CPU-heavy but not urgent, you can lower its priority so the system stays responsive.

---

## 7) /proc: the “truth” behind the tools

`/proc` is a virtual filesystem exposing kernel process info.

Useful files:
- `/proc/<pid>/status` (state, threads, memory)
- `/proc/<pid>/cmdline` (real argv)
- `/proc/<pid>/fd/` (open FDs)
- `/proc/<pid>/io` (read/write bytes)
- `/proc/loadavg` (system load)

Example:
```bash
pid=1234
cat /proc/$pid/status
ls -l /proc/$pid/fd | head
cat /proc/$pid/io
```
