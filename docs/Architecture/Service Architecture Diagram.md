# GSX Infrastructure Architecture Overview (Week 6 Handoff)

**Week 6 architecture overview**.

It is designed to match the assignment requirement for a system diagram with **server, storage, backups, users, and data/dependency flows**.

---

## 1. Architecture summary

The final design is a **single Debian server** administered through **SSH**, managed with **Git-tracked configuration**, and operated through a **systemd-centric runtime model**.

The server has two storage layers:

- **Primary system disk**: operating system, active configuration, user homes, shared team workspace, Nginx, and the administration repository/runtime tree.
- **Dedicated backup disk** mounted at `/srv/week5-data`: stores snapshot backups and restore-test data separately from the root filesystem.

Operationally, the system is built around five ideas:

1. **Remote administration and hardening** via OpenSSH and sudo.
2. **Configuration as code** through a repo-backed `etc/`, `opt/`, and `docs/` structure.
3. **Reliable services and automation** through `systemd` units and timers.
4. **Least-privilege collaboration** with users, groups, ACLs, and PAM limits.
5. **Recoverability** through automated snapshot backups and scheduled restore verification.

---

## 2. High-level system diagram

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                                USERS / ADMINS                               │
│                                                                              │
│   gsx (ops/admin)              dev1  dev2  dev3  dev4 (greendevcorp team)   │
│   - sudo access                - private homes                              │
│   - Git / automation           - shared collaboration area                  │
└───────────────────────────────┬──────────────────────────────────────────────┘
                                │
                                │ SSH (port 2222, key-based, root login disabled)
                                ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                           DEBIAN SERVER                                      │
│                                                                              │
│  ┌───────────────────────────── Control Plane ────────────────────────────┐  │
│  │ OpenSSH                                                                │  │
│  │ sudo                                                                   │  │
│  │ unattended upgrades                                                    │  │
│  │ Git-tracked admin repo                                                 │  │
│  │   /home/gsx/gsx-admin  (source of truth)                               │  │
│  │ published/mirrored runtime tree                                        │  │
│  │   /srv/gsx-admin/{opt,etc,docs,logs,state}                             │  │
│  └─────────────────────────────┬───────────────────────────────────────────┘  │
│                                │                                              │
│                                │ installs / publishes                        │
│                                ▼                                              │
│  ┌──────────────────────────── Runtime / Services ────────────────────────┐  │
│  │ systemd                                                                │  │
│  │   ├─ nginx.service (+ restart policy)                                  │  │
│  │   ├─ nginx_setup.service/.timer                                         │  │
│  │   ├─ gsx-workload.service (CPU/memory/tasks limits via cgroups)        │  │
│  │   ├─ gsx-backup.service/.timer   [Week 2 legacy tar backup]            │  │
│  │   ├─ gsx-backup-tot.service/.timer [Week 5 final snapshot backup]      │  │
│  │   └─ gsx-backup-tot-verify.service/.timer [restore verification]       │  │
│  └─────────────────────────────┬───────────────────────────────────────────┘  │
│                                │                                              │
│                    logs/status │ journalctl / systemctl                      │
│                                ▼                                              │
│  ┌────────────────────────── Observability Layer ─────────────────────────┐  │
│  │ journald                                                               │  │
│  │ logrotate / journald retention                                         │  │
│  │ evidence logs under /srv/gsx-admin/logs                                │  │
│  │   ├─ backups/                                                          │  │
│  │   └─ workload/                                                         │  │
│  └─────────────────────────────┬───────────────────────────────────────────┘  │
│                                │                                              │
│                                │ reads/writes                                │
│                                ▼                                              │
│  ┌────────────────────────── User Data Layer ─────────────────────────────┐  │
│  │ /home/gsx                                                              │  │
│  │ /home/dev1 ... /home/dev4 (0700 private homes)                         │  │
│  │ /home/greendevcorp                                                     │  │
│  │   ├─ bin/    (2750, team-executable)                                   │  │
│  │   ├─ shared/ (3770, setgid + sticky, shared workspace)                 │  │
│  │   └─ done.log (dev1 writable, team readable via ACL/policy)            │  │
│  └─────────────────────────────┬───────────────────────────────────────────┘  │
└────────────────────────────────┼──────────────────────────────────────────────┘
                                 │
                                 │ backup source data
                                 ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                     DEDICATED BACKUP STORAGE (/srv/week5-data)              │
│                                                                              │
│  /srv/week5-data/gsx-backups/                                                │
│    ├─ snapshots/<timestamp>/                                                 │
│    │   ├─ data/                                                              │
│    │   └─ metadata/                                                          │
│    ├─ restore-tests/                                                         │
│    └─ latest -> most recent snapshot                                         │
│                                                                              │
│  backup flow:                                                                │
│    gsx-backup-tot.timer  →  gsx-backup-tot.service  →  18-run-backup.sh     │
│    gsx-backup-tot-verify.timer → verify service → 19-verify-backups.sh      │
└────────────────────────────────┬─────────────────────────────────────────────┘
                                 │
                                 │ optional third copy (3-2-1)
                                 ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│                      OPTIONAL OFFSITE / SECOND LOCATION                     │
│                                                                              │
│  OFFSITE_DIR mirror of latest snapshot                                      │
│  Examples: second VM mount, shared folder, or NFS-backed location           │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Component breakdown

| Layer | Component | Purpose | Main paths / units |
|---|---|---|---|
| Access | OpenSSH | Remote administration for both team members | `/etc/ssh/sshd_config.d/gsx-hardening.conf` |
| Security | sudo + no-root-login | Privilege escalation without direct root SSH access | Week 1 hardening |
| Source of truth | Admin repo | Stores scripts, configs, and docs in version control | `/home/gsx/gsx-admin` |
| Published runtime | Admin runtime tree | Stable operational location mirrored to `/srv` | `/srv/gsx-admin` |
| Service manager | systemd | Starts services, enforces dependencies, runs timers | `/etc/systemd/system/` |
| Web tier | Nginx | Example always-on service with restart policy | `nginx.service.d/override.conf` |
| Observability | journald + logrotate | Central log collection and retention control | `journalctl`, `/etc/logrotate.d/gsx-admin` |
| Performance demo | gsx-workload.service | Signal-aware workload with cgroup limits | `gsx-workload.service` |
| Team access model | greendevcorp + ACLs | Shared collaboration with least privilege | `/home/greendevcorp/*`, `/etc/profile.d/greendevcorp.sh`, `/etc/security/limits.conf` |
| Backup (early) | gsx-backup | Week 2 timer/service backup pipeline | `gsx-backup.service`, `gsx-backup.timer` |
| Backup (final) | gsx-backup-tot | Week 5 snapshot backup system on dedicated disk | `gsx-backup-tot.service`, `gsx-backup-tot.timer` |
| Recovery validation | gsx-backup-tot-verify | Scheduled restore verification and integrity checks | `gsx-backup-tot-verify.service`, `gsx-backup-tot-verify.timer` |
| Backup storage | Dedicated disk | Keeps recovery data off the root filesystem | `/srv/week5-data` |

---

## 4. Main data flows and dependencies

### 4.1 Administration flow

```text
Admin workstation
  → SSH
  → Debian server
  → Git repo (/home/gsx/gsx-admin)
  → setup scripts in opt/
  → installed config in /etc
  → published operational copy in /srv/gsx-admin
```


### 4.2 Service and observability flow

```text
systemd
  → starts nginx / workload / backup services
  → captures stdout/stderr in journald
  → operators inspect with systemctl + journalctl
  → evidence logs kept under /srv/gsx-admin/logs
```

### 4.3 User and permission flow

```text
dev1..dev4
  → authenticate locally / via SSH (as configured)
  → inherit group greendevcorp
  → shared PATH and aliases from /etc/profile.d/greendevcorp.sh
  → resource limits from PAM limits.conf
  → collaborate in /home/greendevcorp/shared
```

Permission model:

- private homes isolate personal data
- `greendevcorp` provides team-level access
- `setgid` keeps shared files in the team group
- `sticky bit` prevents users deleting each other’s files in the shared directory
- `done.log` restricts writes to the authorized user while keeping team read access

### 4.4 Backup and recovery flow

```text
Production data
  (/etc, /home/*, /srv/gsx-admin, /var/www)
      │
      ▼
gsx-backup-tot.timer
      ▼
gsx-backup-tot.service
      ▼
18-run-backup.sh
      ▼
/srv/week5-data/gsx-backups/snapshots/<timestamp>/
      ├─ data/
      └─ metadata/
      ▼
latest symlink updated
      ▼
optional OFFSITE_DIR sync
```

Verification flow:

```text
gsx-backup-tot-verify.timer
  → gsx-backup-tot-verify.service
  → 19-verify-backups.sh
  → checksum validation
  → restore to alternate path
  → inventory comparison
  → verification evidence log
```

---

## 5. Why this architecture makes sense

### 5.1 Single-server design


- remote operations
- service management
- observability
- user and permission control
- storage separation
- backup and recovery testing


### 5.2 Repo-backed + mirrored `/srv/gsx-admin` design

Keeping configuration and scripts in the repo gives reproducibility. Publishing them under `/srv/gsx-admin` gives a stable runtime location for services, logs, and operations.

That separation is useful because:

- the repo is the editable source of truth
- `/etc` is the active system configuration
- `/srv/gsx-admin` is the operational handoff layer another sysadmin can inspect quickly

### 5.3 systemd-centric runtime

Using `systemd` as the center of the runtime model gives:

- service supervision
- boot-time enablement
- restart policies
- timer-based automation
- built-in observability through `journalctl`
- cgroup-based resource control

So the system is easier to monitor and easier to recover.

### 5.4 Separate backup disk

Storing backups on `/srv/week5-data` instead of the root filesystem reduces one of the biggest failure modes: losing both production data and backups in the same filesystem incident.

Using the  3-2-1 principle:

- copy 1: live system data
- copy 2: dedicated local backup disk
- copy 3: optional offsite/second-location mirror

---

## 6. Trade-offs and limitations

### Kept intentionally simple

This project uses one main VM instead of splitting web, application, and backup roles across multiple servers. That is simpler to build, but it means the architecture does not yet provide true service isolation.

### Backup design optimized for restore simplicity

The final backup stack uses **rsync hard-link snapshots** rather than tar-only incrementals. This is a good fit for the assignment because each snapshot looks like a full tree and is easy to restore, but it is less space-efficient than more advanced enterprise backup systems.


### Offsite copy is optional, not guaranteed by default

The design supports a third copy through `OFFSITE_DIR`, but whether that copy exists depends on having a second storage location configured.

---

## 7. How this would scale

### To 20 users

- keep the same structure
- add more role-based groups (`developers`, `ops`, `contractors`)
- move more permission exceptions into ACLs
- add better disk monitoring and backup alerting
- separate documentation for onboarding/offboarding

### To 100 users

At that point, the architecture should evolve toward:

- centralized identity management (LDAP/SSO)
- separate application and backup hosts
- real monitoring/alerting stack
- immutable backups or object storage
- configuration management tooling beyond Bash
- networked shared storage with stronger access controls

---

