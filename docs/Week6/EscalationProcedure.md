# Escalation Procedure

This runbook defines **when to call for help, what evidence to collect first, and who should be contacted next** during operational incidents.

---

## 1. Goal

Escalation is required when an issue:

- risks **data loss**
- causes **service unavailability** that the current operator cannot fix safely
- affects **access control or security**
- blocks **backup, restore, or recovery validation**
- requires a change that is outside the current operator’s confidence or authority

The objective is to reduce recovery time **without making the incident worse**.

---

## 2. Escalation levels

### Level 1 — Local operator

The administrator currently working on the VM.

Use Level 1 first for:

- routine service restarts
- reading logs
- checking timers
- checking disk, memory, CPU, and permissions
- rerunning idempotent verification scripts

Typical evidence to gather first:

```bash
date --iso-8601=seconds
hostnamectl
systemctl --failed --no-pager
journalctl -p err -n 100 --no-pager
```

### Level 2 — Project maintainer / teammate

Escalate to the other project maintainer when:

- the service still fails after standard runbooks
- the problem may require editing tracked scripts or unit files
- backups or restore verification fail repeatedly
- there is uncertainty about the intended design

Provide:

- what changed just before the issue started
- which commands were run
- exact unit names affected
- recent relevant logs
- whether the issue is reproducible

### Level 3 — Instructor / supervisor

Escalate to course staff when:

- both student maintainers are blocked
- there is a suspected security incident
- the grading environment or provided lab constraints are the blocker
- the VM, disk, or host integration behaves inconsistently with the documented setup

At this level, include a concise incident summary and attach the evidence already collected.

---

## 3. Incidents that must be escalated immediately

Do **not** keep experimenting alone if any of the following happens:

- the backup disk is missing, unmountable, or appears corrupted
- the latest snapshot cannot be restored or its manifest fails validation
- SSH access for all admins is lost
- `/etc/sudoers*` changes break sudo access
- permissions expose private developer homes to other users
- an unknown process, unexpected login, or suspicious file change suggests compromise
- the system is close to a destructive action such as overwriting `/etc`, `/home`, or `/srv` from an unverified restore

---

## 4. Evidence checklist before escalation

Capture the smallest useful bundle of evidence first.

### Service state

```bash
systemctl status <unit> --no-pager
systemctl show <unit> -p ActiveState -p SubState -p Result -p ExecMainStatus
journalctl -u <unit> -n 120 --no-pager -o short-iso
```

### Backup / restore state

```bash
find /srv/week5-data/gsx-backups/snapshots -maxdepth 1 -mindepth 1 -type d | sort | tail
ls -lah /srv/week5-data/gsx-backups
journalctl -u gsx-backup-tot.service -n 120 --no-pager
journalctl -u gsx-backup-tot-verify.service -n 120 --no-pager
```

### Host health

```bash
uptime
free -h
df -h
ps -eo pid,ppid,pcpu,pmem,stat,comm --sort=-pcpu | head -n 15
```

### Access / permission state

```bash
id <user>
ls -ld /home/<user> /home/greendevcorp /home/greendevcorp/shared
getfacl /home/greendevcorp/done.log
```

---

## 5. Communication template

Use this format when escalating:

```text
Incident: <one-line summary>
Started: <date/time>
Impact: <who or what is affected>
What changed: <recent script, deploy, config, reboot, package update>
What I checked: <commands/runbooks already used>
Current evidence: <most relevant errors or logs>
Risk: <data loss / outage / security / uncertain restore>
Help needed: <what decision or action is needed>
```

---

## 6. Decision rules

- Prefer **read-only diagnostics first**.
- Prefer **graceful service control** over force-killing processes.
- Never overwrite production paths from a restore **before** manifest verification passes.
- If sudo or SSH access is at risk, stop and escalate before editing access control again.
- If the issue touches both configuration and data integrity, treat it as a recovery-risk incident.

---

## 7. Related runbooks

- `docs/Runbooks/check-service-logs.md`
- `docs/Runbooks/verify-timers.md`
- `docs/Runbooks/troubleshoot-slow-server.md`
- `docs/Runbooks/debug-shared-file-access.md`
- `docs/Runbooks/DisasterRecoveryRunbook.md`
