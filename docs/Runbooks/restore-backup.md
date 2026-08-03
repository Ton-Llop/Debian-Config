# Runbook — Restore From Backup

## 0) Locate the latest backup

```bash
ls -lt /srv/gsx-admin/backups | head -n 20
```

You will typically see one of:
- `week1-sensitive-<TS>.tar` + `.tar.sha256` (plaintext)
- `week1-sensitive-<TS>.tar.gpg` + `.tar.gpg.sha256` (encrypted)

---

## 1) Verify checksum

Plaintext:

```bash
cd /srv/gsx-admin/backups
sha256sum -c week1-sensitive-<TS>.tar.sha256
```

Encrypted:

```bash
cd /srv/gsx-admin/backups
sha256sum -c week1-sensitive-<TS>.tar.gpg.sha256
```

If checksum fails:
- treat the backup as corrupted
- investigate storage / disk errors
- verify the previous backup in the chain

---

## 2) Restore to an alternate location

Create a restore target:

```bash
sudo mkdir -p /tmp/gsx-restore-test
sudo chmod 0700 /tmp/gsx-restore-test
```

### A) Plaintext restore

```bash
sudo tar -xpf /srv/gsx-admin/backups/week1-sensitive-<TS>.tar -C /tmp/gsx-restore-test
```

### B) Encrypted restore (stream decrypt)

```bash
sudo gpg --decrypt /srv/gsx-admin/backups/week1-sensitive-<TS>.tar.gpg | \
  sudo tar -xpf - -C /tmp/gsx-restore-test
```

Notes:
- This prompts for passphrase unless the environment provides it.
- For systemd automated encryption, passphrase should be stored in `/etc/gsx-admin/backup.env`.

---

## 3) Sanity-check restored content

Example checks:

```bash
sudo ls -lah /tmp/gsx-restore-test/etc/ssh 2>/dev/null || true
sudo ls -lah /tmp/gsx-restore-test/srv/gsx-admin 2>/dev/null || true
```

---

## 4) Cleanup

```bash
sudo rm -rf /tmp/gsx-restore-test
```
