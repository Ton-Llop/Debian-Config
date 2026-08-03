# Backup Automation

This repo uses:
- a Week 1 backup script (`opt/04-backup-secrets.sh`) published to `/srv/gsx-admin/opt/`
- a systemd oneshot service (`gsx-backup.service`) that runs the script
- a systemd timer (`gsx-backup.timer`) that schedules it daily
- optional encryption configured via a root-only env file (`/etc/gsx-admin/backup.env`), only accessible on the machine.

---

## 1) Backup script

Repo script:
- `opt/04-backup-secrets.sh`

What it does:
- Creates a tar archive of “sensitive-ish” host artifacts (SSH config, sudoers, hostname/hosts, admin filesystem, SSH keys under `/home/gsx/.ssh`)
- Stores backups under `/srv/gsx-admin/backups/`
- Writes a SHA256 checksum next to the artifact

Encryption behavior (GPG):
- Default: `ENCRYPT_MODE=auto`
  - Encrypt if `PASSPHRASE` is set (non-interactive) OR a TTY exists (interactive)
  - Otherwise fall back to plaintext tar + checksum (so the timer doesn’t fail on headless runs)

---

## 2) systemd unit files (service + timer)

Repo-backed:
- `etc/systemd/system/gsx-backup.service`
- `etc/systemd/system/gsx-backup.timer`

Installed to:
- `/etc/systemd/system/gsx-backup.service`
- `/etc/systemd/system/gsx-backup.timer`

Scheduling (timer):
- Runs daily at **03:30** (server local time)
- `Persistent=true` means missed runs occur after reboot
- `RandomizedDelaySec=10m` reduces predictable “thundering herd” patterns

Logs:
- All service output goes to journald automatically.

---

## 3) Secrets layer: /etc/gsx-admin/backup.env (NOT in Git)

Why this file exists:
- We want encrypted backups without committing secrets into Git.
- systemd supports loading environment variables from an `EnvironmentFile=`.

Example in repo:
- `etc/gsx-admin/backup.env.example`

Real file on the server:
- `/etc/gsx-admin/backup.env` (permissions `0600 root:root`)

Created by automation script:
- `opt/08-backup-automation.sh` (prompts for a passphrase and creates the file if missing)

---

## 4) Install + enable backup automation

Run:

```bash
sudo bash opt/08-backup-automation.sh
```

This will:
- publish scripts to `/srv/gsx-admin/opt/`
- install systemd units into `/etc/systemd/system/`
- create `/etc/gsx-admin/backup.env` if missing
- enable + start the timer
- (by default) trigger one run immediately for verification

To install but not run immediately:

```bash
sudo RUN_NOW=0 bash opt/08-backup-automation.sh
```

---

## 5) Verification (evidence output)

Script:
- `opt/09-verify-backup.sh`

Run:

```bash
sudo bash opt/09-verify-backup.sh
```

This writes:
- `/srv/gsx-admin/logs/week2-backup-verify-<timestamp>.log`

And includes:
- timer status and next/last run
- last service logs
- last service Result/ExitStatus
- most recent backup artifacts + checksum verification

---

## 6) Quick restore test (recommended)

Plaintext backup example:

```bash
cd /srv/gsx-admin/backups
sha256sum -c week1-sensitive-<TS>.tar.sha256
sudo mkdir -p /tmp/restore-test
sudo tar -xpf week1-sensitive-<TS>.tar -C /tmp/restore-test
```

Encrypted backup example:

```bash
cd /srv/gsx-admin/backups
sha256sum -c week1-sensitive-<TS>.tar.gpg.sha256
sudo mkdir -p /tmp/restore-test

# prompts for passphrase unless you set it via env
sudo gpg --decrypt week1-sensitive-<TS>.tar.gpg | sudo tar -xpf - -C /tmp/restore-test
```

Runbook:
- `docs/Runbooks/restore-backup.md`
