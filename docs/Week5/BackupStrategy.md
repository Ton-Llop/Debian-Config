# Week 5 — Backup Strategy

## Goal

Protect the GreenDevCorp server against the most likely failure scenarios:

- accidental deletion by developers or administrators
- corruption of configuration files
- failure of the main VM disk
- rollback after a bad change
- recovery after malware or ransomware affecting the primary filesystem

## Data that must be backed up

### Priority 1 — configuration and infrastructure state

- `/etc`
- `/srv/gsx-admin`
- `/var/www` (if present)

These paths define how the server is built and operated. Losing them would make rebuilds slower and risk configuration drift.

### Priority 2 — user and team data

- `/home/gsx`
- `/home/greendevcorp`
- `/home/dev1`
- `/home/dev2`
- `/home/dev3`
- `/home/dev4`

These paths contain shell data, shared work, and developer-created files.

### Not included by default

- `/tmp`, `/var/tmp`, caches, trash directories
- backup destination paths themselves
- very large transient data that can be regenerated

## Chosen strategy

We use **incremental snapshots with rsync + hard links**.

### Why this instead of full tar every day?

A daily full backup would be simple, but it would waste disk space and make retention expensive.

### Why this instead of GNU tar incremental chains?

Tar incrementals reduce storage, but restore is more complex because a restore may depend on the full backup plus several incrementals.

### Why rsync snapshots fit this assignment?

- storage-efficient: unchanged files are hard-linked
- simple restores: each snapshot looks like a full filesystem tree
- easy inspection during the oral interview
- works well with a second VirtualBox disk mounted in Debian

## Retention policy

- keep **daily** snapshots for **7 days**
- keep **weekly** snapshots (Sunday) for **4 weeks**
- keep **monthly** snapshots (day 1) for **3 months**

This balances recovery flexibility with the limited storage of a lab VM.

## 3-2-1 application

### Copy 1

Production data on the main VM disk.

### Copy 2

Local snapshot backups on the dedicated Week 5 filesystem mounted at `/srv/week5-data`.

### Copy 3

Optional offsite or second-location mirror using `OFFSITE_DIR` in `/etc/gsx-admin/backup-tot.env`.
Examples:

- a VirtualBox shared folder on the host
- an NFS mount from a second VM
- another mounted disk path

## RPO / RTO

### RPO (maximum acceptable data loss)

Target: **24 hours**.

Reason: the timer runs daily. In the worst normal case, recovery loses at most the work since the last successful backup.

### RTO (maximum acceptable recovery time)

Target: **under 1 hour** for this lab environment.

Reason: snapshots are directly browsable and can be restored with `rsync` instead of rebuilding backup chains.

## Trade-offs to defend in the interview

- We optimized for **simple restore and verification**, not for minimal backup size.
- We kept retention short because VM storage is limited.
- We designed support for the third 3-2-1 copy through `OFFSITE_DIR`, but the actual medium depends on what extra storage the lab provides.
- For live databases, this design would need an application-aware dump step before backup.
