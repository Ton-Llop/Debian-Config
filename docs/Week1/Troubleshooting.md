# Troubleshooting (GSX Week 1)

This document covers common issues when running the Week 1 workflow:

- **`03-verify.sh`** (entrypoint): clones the repo (if needed), runs:
  - **`01-install-packages.sh`**
  - **`02-setup-admin-dirs.sh`**
- Then validates hardening (SSH, sudo, unattended upgrades, etc.) and baseline state.

---

## Quick diagnostics checklist

Run these commands first to narrow the problem quickly:

```bash
# Identity / context
pwd
whoami
id

# Scripts: line endings / interpreter
file 03-verify.sh 01-install-packages.sh 02-setup-admin-dirs.sh
head -n 5 03-verify.sh

# SSH state (expect 2222 if hardened)
ss -lntp | grep -E '(:22|:2222)\b' || true
systemctl status ssh --no-pager || true
journalctl -u ssh -n 80 --no-pager || true

# Unattended upgrades state
systemctl status unattended-upgrades --no-pager 2>/dev/null || true
systemctl list-timers --all | grep -E 'apt|unattended' || true

# Git sanity (adjust repo path if needed)
git -C /home/gsx/gsx-admin status 2>/dev/null || true
git -C /home/gsx/gsx-admin remote -v 2>/dev/null || true
```

---

## Possible issues list with fixes

## 1) `set: pipefail: invalid option name` (CRLF / `^M`)

**Symptom**
- Script fails immediately with:
  - `line 2: set: pipefail: invalid option name`

**Cause**
- The script has Windows line endings (**CRLF**). Bash reads `pipefail\r`.

**Fix**
Run on Debian:

```bash
sed -i 's/\r$//' 03-verify.sh
sed -i 's/\r$//' 01-install-packages.sh
sed -i 's/\r$//' 02-setup-admin-dirs.sh
```

**Confirm**
```bash
file 03-verify.sh
# should NOT say "with CRLF line terminators"
```

**Prevent**
Add `.gitattributes` to the repo:

```gitattributes
*.sh text eol=lf
```

---

## 2) `Permission denied` when running scripts

**Symptom**
- `./03-verify.sh: Permission denied`

**Causes**
- Execute bit missing, or filesystem is mounted `noexec` (common on shared folders).

**Fix**
```bash
chmod +x 03-verify.sh
bash ./03-verify.sh
```

**Note**
- On `noexec` mounts, always run via `bash ./script.sh` even if it’s executable.

---

## 3) “Setup already running” / script lock issues

**Symptom**
- Script exits with a message like “Setup already running.”

**Cause**
- Another instance of Week 1 scripts is running (shared `flock` lock file).

**Fix**
Check running processes:
```bash
ps aux | grep -E '0[123]-|verify\.sh' | grep -v grep
```

Check lock holder:
```bash
sudo lsof /var/lock/gsx-week1.lock 2>/dev/null || true
```

---

## 4) APT / dpkg lock errors

**Symptom**
- `Could not get lock /var/lib/dpkg/lock-frontend`
- `Unable to acquire the dpkg frontend lock`

**Cause**
- `apt-daily`, `unattended-upgrades`, PackageKit, or another apt process is running.

**Fix (safe approach)**
Identify the holder:
```bash
sudo lsof /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock 2>/dev/null || true
ps aux | egrep 'apt|dpkg|unattended' | grep -v egrep || true
```

Optionally stop background services (temporary) and retry:
```bash
sudo systemctl stop apt-daily.service apt-daily.timer 2>/dev/null || true
sudo systemctl stop apt-daily-upgrade.service apt-daily-upgrade.timer 2>/dev/null || true
sudo systemctl stop unattended-upgrades 2>/dev/null || true
sudo systemctl stop packagekit 2>/dev/null || true
```

**Avoid**
- Don’t kill `dpkg` unless you know exactly what you’re doing (can corrupt package state).

---

## 5) Git clone fails (auth / key / URL)

**Symptoms**
- `Permission denied (publickey)`
- `Repository not found`
- `fatal: could not read Username...`
- clone “hangs” waiting for credentials

**Fix checklist**
Validate remote reachability:
```bash
GIT_TERMINAL_PROMPT=0 git ls-remote <REMOTE_URL>
```

If using SSH:
```bash
ssh -T git@github.com
```

If using HTTPS:
- GitHub typically requires a Personal Access Token (PAT) instead of a password for private repos.

---

## 6) Repo exists already (clone conflicts / wrong directory)

**Symptom**
- Script expects cloning but directory already exists, or uses the wrong path.

**Fix**
Ensure you treat **repo root** as the full repo directory (e.g. `/home/gsx/gsx-admin`) and not the parent.

Sanity:
```bash
ls -la /home/gsx
ls -la /home/gsx/gsx-admin
git -C /home/gsx/gsx-admin status
```

---

## 7) SSH unreachable after hardening (port 2222)

### 7.1 Can’t connect on port 2222

**Symptoms**
- `Connection refused` or timeout on `2222`

**Check server listening**
```bash
ss -lntp | grep sshd
sudo systemctl status ssh --no-pager
```

**Validate sshd effective config**
```bash
sudo sshd -T | grep -E 'port|passwordauthentication|permitrootlogin'
```

**Restart**
```bash
sudo systemctl restart ssh
```

### 7.2 Firewall / NAT not allowing 2222

Even if sshd listens on 2222 locally, you still need:
- server firewall rule (e.g. UFW)
- hypervisor NAT / port-forwarding
- router / cloud security group rule

Server firewall check:
```bash
sudo ufw status verbose 2>/dev/null || true
```

Allow 2222 (if using UFW):
```bash
sudo ufw allow 2222/tcp
```

---

## 8) Disabled password auth and got locked out

**Symptom**
- You disabled password auth, but key auth doesn’t work, so you can’t SSH in.

**Fix**
Use VM console access and temporarily re-enable:
- `PasswordAuthentication yes`
- `PubkeyAuthentication yes`

Then fix authorized keys + permissions:
```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

---

## 9) Root login blocked

**Symptom**
- `ssh root@host` fails

**Cause**
- Expected if `PermitRootLogin no` is set.

**Fix**
- SSH as `gsx` (or admin user), then:
```bash
sudo -i
```

---

## 10) Sudo / admin group not working

**Symptoms**
- “user is not in the sudoers file”
- `gsx` cannot sudo after scripts

**Check**
```bash
id gsx
getent group sudo
getent group gsx-admin
```

**Fix (recommended: sudoers.d)**
```bash
echo '%gsx-admin ALL=(ALL:ALL) ALL' | sudo tee /etc/sudoers.d/gsx-admin
sudo chmod 440 /etc/sudoers.d/gsx-admin
sudo visudo -c
```

**Note**
- Re-login may be required for group membership to apply.

---

## 11) `fatal: detected dubious ownership in repository` (Git safe.directory)

**Symptom**
- Git refuses to operate due to “dubious ownership”.

**Cause**
- Repo owned by a different user (common if cloned as `root`, then used as `gsx`).

**Fix**
```bash
sudo chown -R gsx:gsx /home/gsx/gsx-admin
git config --global --add safe.directory /home/gsx/gsx-admin
```

---

## 12) Git credential prompts break automation (non-interactive auth)

**Symptom**
- Script hangs or fails while Git tries to prompt for credentials.

**Cause**
- Non-interactive environment, or `sudo` context can’t access your credential helper.

**Fix**
Test non-interactive access:
```bash
GIT_TERMINAL_PROMPT=0 git ls-remote <REMOTE_URL>
```

If it fails:
- use SSH keys, or
- use an HTTPS token in a safe way (avoid storing plaintext in scripts).

---

## 13) DNS/network issues: cannot resolve GitHub or Debian mirrors

**Symptoms**
- `Could not resolve host: github.com`
- `Temporary failure resolving 'deb.debian.org'`

**Fix**
```bash
ping -c 1 1.1.1.1
ping -c 1 github.com
cat /etc/resolv.conf
```

---

## 14) TLS/HTTPS failures due to incorrect system time (clock skew)

**Symptoms**
- TLS errors like “certificate is not yet valid” / “expired”

**Fix**
```bash
timedatectl status
sudo timedatectl set-ntp true
sudo systemctl restart systemd-timesyncd
```

---

## 15) `apt-get update` fails with `NO_PUBKEY` / signature errors

**Symptom**
- APT refuses updates due to missing keys or invalid signatures.

**Fix**
Identify sources:
```bash
grep -R "deb " /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null
sudo apt-get update
```

Then remove/fix the offending repo entry and retry.

---

## 16) SSH won’t restart after config changes (sshd_config syntax error)

**Symptom**
- `systemctl restart ssh` fails after editing sshd config.

**Fix**
Validate config before restart:
```bash
sudo sshd -t
```

Only restart if validation passes:
```bash
sudo systemctl restart ssh
```

---

## 17) Port changed to 2222 but still unreachable (NAT/forwarding/firewall mismatch)

**Symptom**
- `sshd` listens on 2222 locally, but you can’t connect externally.

**Cause**
- Outside-layer networking not configured (VM NAT rule, router, cloud SG).

**Fix**
Server-side:
```bash
ss -lntp | grep sshd
sudo ufw status verbose 2>/dev/null || true
```

Then verify your VM/hypervisor port forwarding (host -> guest 2222) or cloud security group allows TCP 2222.

---

## 18) SSH key auth fails due to permissions or wrong user home

**Symptom**
- `Permission denied (publickey)` even with the right key.

**Fix**
On the server, ensure correct ownership and permissions for the target user:
```bash
getent passwd gsx | cut -d: -f1,6
sudo ls -la /home/gsx/.ssh
sudo chmod 700 /home/gsx/.ssh
sudo chmod 600 /home/gsx/.ssh/authorized_keys
sudo chown -R gsx:gsx /home/gsx/.ssh
```

---

## 19) `Host key verification failed` / known_hosts mismatch

**Symptom**
- SSH refuses connection after reinstall/rekey of server.

**Fix (on the client)**
```bash
ssh-keygen -R <SERVER_IP_OR_HOSTNAME>
ssh -p 2222 gsx@<SERVER_IP_OR_HOSTNAME>
```

---

## 20) Unattended upgrades “enabled” but not applying updates

**Symptoms**
- `unattended-upgrades` installed/enabled but updates never apply.

**Checks**
```bash
systemctl is-enabled unattended-upgrades 2>/dev/null || true
systemctl status unattended-upgrades --no-pager 2>/dev/null || true
systemctl list-timers --all | grep -E 'apt|unattended' || true
sudo tail -n 200 /var/log/unattended-upgrades/unattended-upgrades.log 2>/dev/null || true
```

**Fix**
Enable timers/services if disabled:
```bash
sudo systemctl enable --now unattended-upgrades
sudo systemctl enable --now apt-daily.timer apt-daily-upgrade.timer
```

---


## 21) APT sources issue (CDROM)

**Symptom**
- “apt-get update prompts for the installation media / fails due to deb cdrom: source”

**Cause**
- the system is trying to update from the installation CD/DVD

**Fix**
Look for a line like "deb cdrom…" If it exists, comment it out.
```bash
sudo grep -R "cdrom:" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null || true
sudo sed -i 's|^deb cdrom:|# deb cdrom:|g' /etc/apt/sources.list
# Update the package
sudo apt-get ...
```

---

## Shared folder edge cases (VirtualBox/VMware)

**Symptoms**
- `sed -i` fails (read-only)
- `chmod +x` doesn’t stick
- scripts don’t run directly

**Fix**
Copy scripts to a local filesystem (e.g. `/tmp`) and run from there:
```bash
cp -a /home/gsx/SharedFolder/03-verify.sh /tmp/03-verify.sh
sed -i 's/\r$//' /tmp/03-verify.sh
bash /tmp/03-verify.sh
```

---

## Reporting an issue

Paste these outputs in your issue/report:

```bash
uname -a
cat /etc/os-release
bash --version | head -n 1
file 03-verify.sh
ss -lntp | grep sshd || true
sudo sshd -T | grep -E 'port|passwordauthentication|permitrootlogin' || true
journalctl -u ssh -n 80 --no-pager || true
systemctl status unattended-upgrades --no-pager 2>/dev/null || true
```