# Week 5 — Backup Verification

## Goal

A backup is only valid if it can be restored and verified.
This verification procedure tests both.

## Verification script

`opt/19-verify-backups.sh`

The script performs four checks:

1. verifies the checksum manifest against the stored snapshot
2. restores the latest snapshot to an alternate path
3. verifies the restored files against the original manifest
4. compares the restored file inventory against the source snapshot inventory

## Alternate restore location

The verification restore happens under:

```text
/srv/week5-data/gsx-backups/restore-tests/
```

This keeps restore testing isolated from production paths.

## Weekly automation

A second systemd stack is included:

- `gsx-backup-tot-verify.service`
- `gsx-backup-tot-verify.timer`

The timer runs weekly so verification is not forgotten.

## Commands to run verification manually

```bash
sudo systemctl start gsx-backup-tot-verify.service
sudo journalctl -u gsx-backup-tot-verify.service -n 120 --no-pager
sudo ls -lt /srv/gsx-admin/logs/backups | head
```

## Evidence produced

The script writes a timestamped verification log to:

```text
/srv/gsx-admin/logs/backups/
```

## What can fail and how we detect it

### Missing snapshot

The verification service fails immediately if no snapshot exists.

### Corrupted snapshot data

`sha256sum -c` fails against `metadata/manifest.sha256`.

### Broken restore procedure

The restore rsync step fails or the restored manifest check fails.

### Incomplete restore

The inventory diff detects missing files even if the service itself completed.
