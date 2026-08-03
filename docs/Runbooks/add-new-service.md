# Runbook — Add a New Service

This runbook explains how to add a new **systemd-managed service** to the GSX project in a way that stays aligned with the repository structure and handoff expectations.

---

## 1. Goal

A new service should be:

- defined in the repo
- reproducible on another machine
- installed through tracked files
- observable with `systemctl` and `journalctl`
- documented so another admin can operate it

---

## 2. Standard design pattern in this repo

Use the same pattern already used by the existing services:

- executable logic in `opt/`
- unit file in `etc/systemd/system/`
- optional environment file in `etc/gsx-admin/`
- runtime/published copy under `/srv/gsx-admin`
- operational documentation in `docs/`

For timer-driven jobs, create both:

- `<name>.service`
- `<name>.timer`

---

## 3. Implementation steps

### Step 1 — Define the service purpose

Write down:

- what the service does
- whether it is long-running or one-shot
- whether it needs a timer
- what files, paths, users, or network access it needs
- what would count as a successful run

### Step 2 — Create or reuse the executable

Add the script under `opt/` if the service runs project-owned logic.

Example:

```bash
opt/21-example-task.sh
```

Requirements for scripts:

- start with `#!/usr/bin/env bash`
- use `set -euo pipefail`
- log meaningful progress and failures
- return a non-zero exit code on error

### Step 3 — Create the unit file

Add a tracked unit under:

```text
etc/systemd/system/<name>.service
```

Minimal example:

```ini
[Unit]
Description=GSX example task
Documentation=/srv/gsx-admin/docs/Week6/AddNewService.md
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=root
Group=root
ExecStart=/usr/bin/bash /srv/gsx-admin/opt/21-example-task.sh
SyslogIdentifier=gsx-example-task
NoNewPrivileges=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
```

For recurring jobs, add a timer such as:

```ini
[Unit]
Description=Run GSX example task on schedule

[Timer]
OnCalendar=hourly
Persistent=true
Unit=gsx-example-task.service

[Install]
WantedBy=timers.target
```

### Step 4 — Add environment configuration only if needed

If the service needs tunable values, create a tracked example file under:

```text
etc/gsx-admin/<name>.env.example
```

Then reference the runtime file from the unit with:

```ini
EnvironmentFile=-/etc/gsx-admin/<name>.env
```

Keep secrets out of Git.

### Step 5 — Publish and install the unit

On the target server:

```bash
sudo install -m 0644 etc/systemd/system/<name>.service /etc/systemd/system/<name>.service
sudo systemctl daemon-reload
```

If there is a timer:

```bash
sudo install -m 0644 etc/systemd/system/<name>.timer /etc/systemd/system/<name>.timer
sudo systemctl daemon-reload
sudo systemctl enable --now <name>.timer
```

If it is a normal service:

```bash
sudo systemctl enable --now <name>.service
```

### Step 6 — Verify behavior

```bash
sudo systemctl status <name>.service --no-pager
sudo journalctl -u <name>.service -n 100 --no-pager
```

If there is a timer:

```bash
sudo systemctl status <name>.timer --no-pager
sudo systemctl list-timers --all | grep <name>
```

### Step 7 — Document it

Update all relevant docs:

- add the service to the architecture overview if it changes the system shape
- add or update a runbook for operating or debugging it
- mention it in the relevant weekly README or final handoff docs

---

## 4. Security and reliability checks

Before considering the new service complete, verify:

- it does not run as root unless required
- it uses the narrowest possible filesystem and privilege access
- it logs enough information for diagnosis
- it fails clearly
- it can be reinstalled cleanly
- it does not hard-code secrets into the repo
- it has sensible ordering/dependency rules

Where appropriate, use systemd hardening such as:

- `NoNewPrivileges=yes`
- `PrivateTmp=yes`
- `ProtectSystem=`
- `ProtectHome=`
- `ReadWritePaths=`

---

## 5. Example validation checklist

- Unit file is tracked in Git
- Script or binary path exists on the target machine
- `systemctl daemon-reload` succeeds
- service starts successfully
- timer triggers successfully, if applicable
- logs are visible in journald
- the service is documented for the next admin

---

## 6. Related files in this repo

Existing examples to model from:

- `etc/systemd/system/gsx-workload.service`
- `etc/systemd/system/gsx-backup-tot.service`
- `etc/systemd/system/gsx-backup-tot.timer`
- `etc/systemd/system/nginx_setup.service`
- `etc/systemd/system/nginx_setup.timer`
