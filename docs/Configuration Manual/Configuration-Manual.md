# Configuration Manual — Fresh Installation

This document explains how to install and configure the full **GSX Foundational Server Administration** environment from scratch on a clean Debian VM.

**Configuration Manual: how to install everything from scratch**
---

## 1. Prerequisites

Before starting, make sure you have:

- A clean Debian VM prepared as in Week 0
- A working user called `gsx`
- `sudo` access from that user
- An optional extra disk for Week 5 backups
- Check [DiscMounting](/docs/Week5/DiscMounting.md)

---

## 2. Install Git and clone the repository

Log in as `gsx` and run:

```bash
sudo apt update
sudo apt install -y git
cd /home/gsx
git clone https://github.com/davidcaran/gsx-admin.git 
cd /home/gsx/gsx-admin
```


---
## 3. Recommended installation method

### Option A — Full automatic setup

This is the fastest method on a fresh machine:

```bash
cd /home/gsx/gsx-admin
sudo bash opt/00-bootstrap-server.sh
```

What it does:

1. Runs the base package and hardening setup
2. Creates the admin directory structure
3. Configures Nginx and service automation
4. Enables logging and observability
5. Configures backup automation
6. Applies resource limits
7. Creates users, groups, ACLs, and shell environment
8. Configures Week 5 dedicated-disk backups
9. Runs verification scripts

The bootstrap script calls these components in sequence: `01-install-packages.sh`, `02-setup-admin-dirs.sh`, `05-nginx_setup.sh`, `06-logging-observability-setup.sh`, `08-backup-automation.sh`, `12-resource-limits-setup.sh`, `15-week4-users-groups-setup.sh`, and `17-backup-setup.sh`

### Option B — Full automatic setup,  skipping system backups

Use this if the extra backup disk is not mounted yet:

```bash
cd /home/gsx/gsx-admin
sudo bash opt/00-bootstrap-server.sh --skip-week5
```

The bootstrap script explicitly supports `--skip-week5`, and otherwise it checks that the Week 5 backup target is mounted before continuing.

### Option C — Provision only, without verification


```bash
sudo bash opt/00-bootstrap-server.sh --setup-only
```

---

## 4. Manual installation, script by script

If you prefer to install the project progressively, run the scripts manually in this order.

### Foundation & Remote Access


```bash
cd /home/gsx/gsx-admin
sudo bash opt/01-install-packages.sh
sudo bash opt/02-setup-admin-dirs.sh
sudo bash opt/03-verify.sh
sudo bash opt/04-backup-secrets.sh
```

### Services, Observability & Automation


```bash
sudo bash opt/05-nginx_setup.sh /home/gsx/gsx-admin
sudo bash opt/06-logging-observability-setup.sh
sudo bash opt/07-verify-logging.sh
sudo bash opt/08-backup-automation.sh
sudo bash opt/09-verify-backup.sh
```

### Process Management & Resource Control

```bash
sudo bash opt/12-resource-limits-setup.sh /home/gsx/gsx-admin
sudo bash opt/13-verify-resource-limits.sh
```

### Users, Groups & Access Control


```bash
sudo bash opt/15-week4-users-groups-setup.sh /home/gsx/gsx-admin
sudo bash opt/16-verify-week4-security.sh
```

### Storage, Backup & Recovery


First make sure the dedicated backup disk is created, formatted, and mounted.

Check [DiscMounting](/docs/Week5/DiscMounting.md)

Then run:

```bash
sudo bash opt/17-backup-setup.sh 
sudo bash opt/19-verify-backups.sh
```

The Week 5 setup script refuses to continue if the backup target is not mounted or if it resolves to the same filesystem as `/`, which protects you from writing backups onto the root disk by mistake. 



---

## 5. Post-install verification

After installation, verify the main services and timers:

```bash
systemctl status nginx
systemctl status gsx-backup.timer
systemctl status gsx-backup-tot.timer
systemctl list-timers --all
journalctl -u nginx -n 50 --no-pager
journalctl -u gsx-backup.service -n 50 --no-pager
```

If you used the full bootstrap script, it already includes a verification phase for Week 1 core and Weeks 2 to 5. 

---

## 6. Repository structure

Main folders:

- `docs/` → documentation and weekly deliverables
- `etc/` → tracked configuration files
- `opt/` → setup, verification, restore, and automation scripts


---

## 7. Useful notes

- Run setup scripts with `sudo bash ...`
- Keep the repository cloned in `/home/gsx/gsx-admin`
- Re-run scripts if needed; configuration is idempotent


---


