# Week 5 — Disaster Recovery Runbook

## Scenario

The primary VM is lost, corrupted, or unbootable, but the Week 5 backup disk still exists.

## Recovery target

Restore the latest verified snapshot onto a rebuilt Debian VM.

## Preconditions

- replacement Debian VM is available
- backup filesystem is attached and mounted at `/srv/week5-data`
- admin repository is present
- root access is available

## Recovery procedure

### 1. Rebuild the base VM

Install Debian, create the `gsx` user, and mount the backup disk.

### 2. Recover the admin repository

Clone the repo or copy it from the backup snapshot under `srv/gsx-admin`.

### 3. Restore the latest snapshot to an alternate location first

```bash
sudo bash opt/20-restore-backup.sh latest /tmp/gsx-disaster-restore
```

### 4. Validate the restored snapshot

```bash
latest_snapshot=$(sudo bash opt/20-restore-backup.sh --list | tail -n 1)
cd /tmp/gsx-disaster-restore
sudo sha256sum -c /srv/week5-data/gsx-backups/snapshots/${latest_snapshot}/metadata/manifest.sha256
```

### 5. Restore into production paths

Use `rsync -aHAX` from `/tmp/gsx-disaster-restore/` back into `/` carefully, or restore selected paths first:

```bash
sudo rsync -aHAX /tmp/gsx-disaster-restore/etc/ /etc/
sudo rsync -aHAX /tmp/gsx-disaster-restore/home/ /home/
sudo rsync -aHAX /tmp/gsx-disaster-restore/srv/ /srv/
```

### 6. Re-enable services

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now nginx
sudo systemctl enable --now gsx-backup.timer
sudo systemctl enable --now gsx-backup-verify.timer
```

### 7. Validate the rebuilt server

```bash
sudo systemctl --failed
sudo systemctl status nginx --no-pager
sudo systemctl status gsx-backup.timer --no-pager
sudo journalctl -u gsx-backup.service -n 50 --no-pager
```

## Estimated timeline

- base VM rebuild: 15–20 minutes
- restore to alternate path: 5–15 minutes (depends on snapshot size)
- production restore and checks: 10–20 minutes

Estimated RTO for the lab environment: **under 1 hour**.

## Recovery notes

- Always restore to an alternate path first.
- Do not overwrite `/etc` directly until the checksum manifest passes.
- If the latest snapshot fails verification, roll back to the previous one.
- If the whole backup disk is unavailable, use the optional offsite mirror configured through `OFFSITE_DIR`.
