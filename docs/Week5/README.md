# Week 5 — Storage, Backup & Recovery

## Included documents

- [DiscMounting](DiscMounting.md)
- [BackupStrategy](BackupStrategy.md)
- [AutomatedBackup](AutomatedBackup.md)
- [BackupVerification](BackupVerification.md)
- [DisasterRecoveryRunbook](../Runbooks/DisasterRecoveryRunbook.md)

## Included scripts

- `opt/17-backup-setup.sh` — installs the Week 5 backup stack
- `opt/18-run-backup.sh` — creates rsync hard-link snapshots
- `opt/19-verify-backups.sh` — verifies integrity and restore procedure
- `opt/20-restore-backup.sh` — restores a selected snapshot to a target path

## Included unit files

- `etc/systemd/system/gsx-backup-tot.service`
- `etc/systemd/system/gsx-backup-tot.timer`
- `etc/systemd/system/gsx-backup-tot-verify.service`
- `etc/systemd/system/gsx-backup-tot-verify.timer`
