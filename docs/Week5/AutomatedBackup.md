# Week 5 — Automated Backup Implementation

## Components

### Script: `opt/17-backup-setup.sh`

Installs packages, validates that `/srv/week5-data` is mounted on a separate filesystem, publishes scripts to `/srv/gsx-admin/opt`, installs systemd units, and enables timers.

### Script: `opt/18-run-backup.sh`

Creates a timestamped snapshot under:

```text
/srv/week5-data/gsx-backups/snapshots/<timestamp>/
```

Each snapshot contains:

- `data/` — restored filesystem tree
- `metadata/backup-info.txt` — backup metadata
- `metadata/files.txt` — inventory of files
- `metadata/manifest.sha256` — checksum manifest
- `metadata/size.txt` and `metadata/filesystem.txt` — evidence for reports

### Service: `gsx-backup-tot.service`

Runs the backup script as a one-shot systemd service and logs to journald.

### Timer: `gsx-backup-tot.timer`

Runs daily at `02:30`, with `Persistent=true` so missed executions are caught after reboot.

## Why journald is enough here

This design logs all runs with a stable `SyslogIdentifier`, so the evidence can be obtained with:

```bash
journalctl -u gsx-backup-tot.service -n 100 --no-pager
```

## Commands to install and run

```bash
sudo bash opt/17-backup-setup.sh
sudo systemctl start gsx-backup-tot.service
sudo systemctl status gsx-backup-tot.timer --no-pager
sudo systemctl list-timers --all | grep gsx-backup-tot
```

## Commands to inspect results

```bash
sudo journalctl -u gsx-backup-tot.service -n 120 --no-pager
sudo find /srv/week5-data/gsx-backups/snapshots -maxdepth 2 -type f | sort | tail -n 30
sudo ls -lah /srv/week5-data/gsx-backups/snapshots
```

## Idempotence notes

- the setup script keeps `/etc/gsx-admin/backup-tot.env` if it already exists
- systemd units are reinstalled safely
- snapshot creation uses a lock file to prevent concurrent runs
- retention cleanup is deterministic and runs after a successful snapshot creation

## Optional offsite copy

If `OFFSITE_DIR` is configured, the latest snapshot is mirrored there after the local snapshot completes.
This is the third copy needed for the 3-2-1 model.
