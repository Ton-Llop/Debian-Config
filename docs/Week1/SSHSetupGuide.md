# WEEK 1  — HOW TO RUN SCRIPTS 01–04 + SSH SETUP (VirtualBox NAT)

## Recommended path: SCRIPT 03 — verify/orchestrate (single entrypoint)

Run as root (from repo root):

```bash
cd /home/gsx/gsx-admin
sudo bash opt/03-verify.sh
```

What it does (summary):
- Runs/validates key parts of the setup (01 + 02) and sanity checks
- Confirms SSH is enabled and listening on the expected port
- Confirms gsx-admin group + sudoers drop-in are correctly installed
- Confirms admin filesystem exists and scripts are published to /srv/gsx-admin/opt

After Script 02, you can also run scripts from the published location:
- `sudo bash /srv/gsx-admin/opt/01-install-packages.sh`
- `sudo bash /srv/gsx-admin/opt/02-setup-admin-dirs.sh`
- `sudo bash /srv/gsx-admin/opt/03-verify.sh`
- `sudo bash /srv/gsx-admin/opt/04-backup-secrets.sh`

------------------------------------------------------------

## Alternative manual path: run scripts 01 → 02 → 03 → 04

## 0) CLONE THE REPO FIRST (required)
Run as user "gsx" in the Debian VM:
```bash
cd /home/gsx
git clone https://github.com/davidcaran/gsx-admin.git
cd gsx-admin
```

Notes:
- This is a PRIVATE repo. You must authenticate (GitHub token/SSH/gh login) when cloning.
- The git repo lives in: /home/gsx/gsx-admin
- The admin filesystem lives in: /srv/gsx-admin (created by Script 02). It is NOT the git repo.
- If you see "dubious ownership" when running git as root, do git commands as user gsx.

------------------------------------------------------------

## 1) SCRIPT 01 — install packages + SSH hardening + unattended upgrades (+ git commit/push)

Run from the repo root:
```bash
cd /home/gsx/gsx-admin
sudo bash opt/01-install-packages.sh
```

What it does (summary):
- Installs base packages (sudo, openssh-server, git, unattended-upgrades, gnupg, etc.)
- Enables the SSH service
- Deploys repo-backed configs from /home/gsx/gsx-admin/etc/ into /etc/
- SSH baseline:
  - SSH listens on port 2222
  - PasswordAuthentication disabled (key-based only)
  - root SSH login disabled
- Commits and pushes changes (best effort)

Quick checks (VM):
```bash
sudo systemctl status ssh --no-pager
sudo ss -lntp | grep 2222
```

------------------------------------------------------------

## 2) SCRIPT 02 — create admin filesystem in /srv (group managed)

Run from the repo root:
```bash
cd /home/gsx/gsx-admin
sudo bash opt/02-setup-admin-dirs.sh
```

What it does (summary):
- Creates group: gsx-admin
- Adds user gsx to group gsx-admin
- Creates admin filesystem (default): /srv/gsx-admin
  - group-readable: /srv/gsx-admin/{opt,etc,docs}
  - group-writable: /srv/gsx-admin/{logs,state,backups}
- Applies group permissions (setgid on directories; restricted access)
- Publishes scripts into: /srv/gsx-admin/opt (so new admins can run them without touching git)

Apply new group membership without relog (optional):
newgrp gsx-admin

Quick checks:
```bash
getent group gsx-admin
groups gsx
ls -ld /srv/gsx-admin /srv/gsx-admin/*
```

------------------------------------------------------------

## 3) SCRIPT 03 — verify/orchestrate (recommended)

Run as root (from repo root):
```bash
cd /home/gsx/gsx-admin
sudo bash opt/03-verify.sh
```

------------------------------------------------------------

## 4) SCRIPT 04 — encrypted backup of Week 1 “sensitive-ish” artifacts

Run as root:
```bash
sudo bash /srv/gsx-admin/opt/04-backup-secrets.sh
or from repo:
sudo bash /home/gsx/gsx-admin/opt/04-backup-secrets.sh
```

What it does (summary):
- Creates a tar archive with selected config/keys:
  - /etc/ssh, /etc/sudoers, /etc/sudoers.d, /etc/hostname, /etc/hosts, /srv/gsx-admin, /home/gsx/.ssh
- Excludes the backups directory itself to avoid “archive cannot contain itself”
- Encrypts the tar using GPG symmetric encryption (AES256) -> .tar.gpg
- Writes a checksum file (.sha256)
- Removes the plaintext .tar after encryption
- Output location:
  - /srv/gsx-admin/backups/week1-sensitive-<UTC_TIMESTAMP>.tar.gpg
  - /srv/gsx-admin/backups/week1-sensitive-<UTC_TIMESTAMP>.tar.gpg.sha256

Notes:
- GPG will prompt for a passphrase ONCE (this passphrase is required to decrypt later).
- If you previously generated .tar files without .gpg due to an error, delete them:
  sudo rm -f /srv/gsx-admin/backups/*.tar

Decrypt example (later):
```bash
gpg --output /tmp/week1.tar --decrypt /srv/gsx-admin/backups/week1-sensitive-XXXX.tar.gpg
tar -tf /tmp/week1.tar
```

------------------------------------------------------------

## SSH SETUP (baseline after Script 01)

SSH config summary:
- SSH listens on port: 2222
- Password authentication is disabled (key-based only)
- Root SSH login is disabled

A) Verify SSH is listening on port 2222 (run in the VM):
```bash
sudo ss -lntp | grep 2222
```

B) Create authorized_keys on the VM (if /home/gsx/.ssh does not exist yet):
```bash
sudo mkdir -p /home/gsx/.ssh
sudo chmod 700 /home/gsx/.ssh
sudo nano /home/gsx/.ssh/authorized_keys
sudo chmod 600 /home/gsx/.ssh/authorized_keys
sudo chown -R gsx:gsx /home/gsx/.ssh
```

(Inside nano: paste your PUBLIC key as ONE single line, save, exit)

C) Generate a key on Windows (OpenSSH Client required)
If your normal "ssh-keygen" is old, use the Windows OpenSSH path explicitly:

`& "$env:WINDIR\System32\OpenSSH\ssh-keygen.exe" -t ed25519`

Show the public key to copy:
```powershell
$env:USERPROFILE\.ssh\id_ed25519.pub`
```

D) VirtualBox NAT Port Forwarding (required if VM IP is 10.0.2.x)
If the VM uses NAT (e.g., IP 10.0.2.15), connect via localhost using port forwarding.

VirtualBox path:
Settings -> Network -> Adapter 1 -> NAT -> Advanced -> Port Forwarding

Add rule (TCP):
- Name: SSH-2222
- Protocol: TCP
- Host IP: 127.0.0.1
- Host Port: 2222
- Guest IP: (leave empty)   [or put the VM IP, e.g., 10.0.2.15]
- Guest Port: 2222

E) Connect from Windows (use modern OpenSSH)
To avoid old SSH clients, run:
```powershell
& "$env:WINDIR\System32\OpenSSH\ssh.exe" -p 2222 gsx@127.0.0.1
```
First connection will ask to accept the host key:
Type: `yes`

(After fixing PATH, you can use: `ssh -p 2222 gsx@127.0.0.1`)

Troubleshooting quick checks:
- On Windows:
```powershell
  Test-NetConnection 127.0.0.1 -Port 2222
  ```
- On Debian:
```bash
  sudo ss -lntp | grep 2222
  sudo systemctl status ssh --no-pager
  ```

Common pitfalls:
- If you try to connect to 10.0.2.x directly from Windows, it will fail under NAT. Use port forwarding + 127.0.0.1.
- If "Permission denied (publickey)", your public key is not correctly placed in `/home/gsx/.ssh/authorized_keys` or permissions are wrong.
- If "Connection refused" on 127.0.0.1:2222, check VirtualBox Port Forwarding rule and confirm sshd is listening on 2222 in the VM.
