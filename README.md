# gsx-admin

Administration repository for the **GSX Foundational Server Administration** project.

This repository contains the tracked configuration, automation scripts, and operational documentation used to provision and operate the Debian server built.

---

## What is in this repo

- `opt/` — setup, verification, backup, restore, and utility scripts
- `etc/` — tracked configuration files and systemd units
- `docs/` — weekly deliverables, runbooks, architecture, and final handoff documentation

The project keeps the **Git repository** under `/home/gsx/gsx-admin` as the source of truth and publishes a stable runtime copy under `/srv/gsx-admin` on the server.

---

## Quick start on a fresh Debian VM

Clone the repo as the `gsx` user:

```bash
sudo apt update
sudo apt install -y git
cd /home/gsx
git clone https://github.com/davidcaran/gsx-admin.git
cd /home/gsx/gsx-admin
```

Run the full bootstrap:

```bash
sudo bash opt/00-bootstrap-server.sh
```

If the dedicated Week 5 backup disk is not mounted yet:

```bash
sudo bash opt/00-bootstrap-server.sh --skip-week5
```

For a step-by-step installation guide, see the [Configuration Manual](docs/Configuration%20Manual/Configuration-Manual.md).

---

## Documentation map

Start here:

- [Documentation index](docs/README.md)
- [Week 6 handoff index](docs/Week6/README.md)
- [Architecture overview](docs/Architecture/Service%20Architecture%20Diagram.md)
- [Configuration Manual](docs/Configuration%20Manual/Configuration-Manual.md)

Key operations docs:

- [Disaster Recovery Runbook](docs/Runbooks/DisasterRecoveryRunbook.md)
- [Restore backup runbook](docs/Runbooks/restore-backup.md)
- [Escalation Procedure](docs/Week6/EscalationProcedure.md)
- [Add New Service runbook](docs/Week6/AddNewService.md)
- [Production Readiness Checklist](docs/Week6/ProductionReadinessChecklist.md)
- [Recovery Test Evidence](docs/Week6/RecoveryTestEvidence.md)

---

## Backup stacks in this project

There are **two** backup implementations in the repo:

- **Week 2 legacy backup**: `gsx-backup.service` / `gsx-backup.timer`
- **Week 5 final backup and verification stack**: `gsx-backup-tot.service`, `gsx-backup-tot.timer`, `gsx-backup-tot-verify.service`, and `gsx-backup-tot-verify.timer`

For recovery procedures, the canonical Week 5 runtime configuration file is:

```text
/etc/gsx-admin/backup-tot.env
```

---

## Notes

- Prefer running setup scripts with `sudo bash ...`.
- Keep shell scripts with **LF** line endings.
- Re-running setup scripts is supported; the repo aims for idempotent provisioning.
