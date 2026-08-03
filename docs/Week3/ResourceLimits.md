# Week 3 — Resource Limits (ulimit + PAM + systemd cgroups)

Goal: prevent a runaway process/service from taking down the whole server.

We use **two layers**:
1. **Per-user limits** (PAM → `/etc/security/limits.conf` → `ulimit` at login)
2. **Per-service limits** (systemd → cgroups v2)

---

## 1) Per-user limits (PAM / limits.conf)

### Soft vs hard limits

- **Soft limit**: default enforced limit; user can lower/raise it *up to* the hard limit.
- **Hard limit**: ceiling; user cannot exceed it.

Typical resources:
- `nofile` (max open FDs)
- `nproc` (max processes)

### Where we configure it

Repo-backed file:
- `etc/security/limits.conf`

We add a managed block for the `gsx-admin` group:
- `@gsx-admin soft nofile 2048`
- `@gsx-admin hard nofile 8192`
- `@gsx-admin soft nproc 512`
- `@gsx-admin hard nproc 1024`

Important:
- These limits apply **only** when PAM sessions load `pam_limits.so`.
- After changing, users need a **new login session** to see the limits.

Check after a new login:
```bash
ulimit -Sn; ulimit -Hn   # nofile soft/hard
ulimit -Su; ulimit -Hu   # nproc  soft/hard
```

---

## 2) Per-service limits (systemd cgroups)

systemd places each service in its own **control group** (cgroup). With cgroup v2, the kernel enforces CPU/memory/task limits.

Unit:
- `etc/systemd/system/gsx-workload.service`

Key directives used:
- `CPUAccounting=yes`, `MemoryAccounting=yes`, `TasksAccounting=yes`
- `CPUQuota=25%` (service gets at most ~25% of 1 CPU)
- `MemoryMax=200M` (hard memory cap)
- `TasksMax=200` (limit threads/processes)

This makes the workload safe to run continuously for demos.

---

## 3) Setup script (what it changes)

Script:
- `opt/12-resource-limits-setup.sh`

What it does:
1. Copies workload script to a stable runtime path:
   - `/srv/gsx-admin/opt/11-workload-signals.sh`
2. Creates and enables `gsx-workload.service` with cgroup limits.
3. Updates `/etc/security/limits.conf` with a managed `gsx-admin` block.
4. Ensures `pam_limits.so` is enabled in the common PAM session files.
5. Mirrors modified `/etc/...` files into:
   - repo: `etc/...`
   - admin share: `/srv/gsx-admin/etc/...`

Tunables (environment variables):
- `GSX_CPU_QUOTA` (default `25%`)
- `GSX_MEMORY_MAX` (default `200M`)
- `GSX_TASKS_MAX` (default `200`)
- `GSX_WORKERS` (default `6`)
- `GSX_NICE` (default `15`)

---

## 4) Evidence: verifying limits are enforced

Verification script:
- `opt/13-verify-resource-limits.sh`

Run:
```bash
sudo bash opt/13-verify-resource-limits.sh gsx-workload.service
```

It prints:
- `systemctl show` fields (CPUQuota/MemoryMax/TasksMax + usage)
- the cgroup path (ControlGroup)
- raw cgroup control files (e.g., `cpu.max`, `memory.max`, `pids.max`)
- a `systemd-cgtop` snapshot (if available)

Manual cgroup evidence:
```bash
CG=$(systemctl show gsx-workload.service -p ControlGroup --value)
sudo cat /sys/fs/cgroup${CG}/cpu.max
sudo cat /sys/fs/cgroup${CG}/memory.max
sudo cat /sys/fs/cgroup${CG}/pids.max
```

---

## 5) ulimit demo (per-shell)

Script:
- `opt/14-ulimit-demo.sh`

Purpose:
- show that `ulimit` changes are per-session and can cause real failures when limits are too low.

Run (low soft FD limit):
```bash
bash opt/14-ulimit-demo.sh 64
```
