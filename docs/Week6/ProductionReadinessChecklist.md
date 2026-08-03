# Production Readiness Checklist

Use this checklist before handing the VM to another administrator or demonstrating that the environment is operationally complete.

---

## 1. Access and baseline security

- [ ] SSH is reachable on the documented port and key-based access works
- [ ] direct root SSH login is disabled
- [ ] sudo access for the intended admin group is working
- [ ] unattended upgrades are configured
- [ ] tracked SSH hardening files are installed from the repo
- [ ] there are no unexpected failed units: `systemctl --failed --no-pager`

## 2. Repo and runtime layout

- [ ] the Git repo exists at `/home/gsx/gsx-admin`
- [ ] the published runtime tree exists at `/srv/gsx-admin`
- [ ] scripts in `/srv/gsx-admin/opt` match the tracked repo version
- [ ] tracked configuration files under `etc/` are installed in the expected system paths

## 3. Core services and timers

- [ ] `nginx` starts successfully and passes `nginx -t`
- [ ] the Week 2 backup timer works: `gsx-backup.timer`
- [ ] the Week 5 final backup timer works: `gsx-backup-tot.timer`
- [ ] the Week 5 verification timer works: `gsx-backup-tot-verify.timer`
- [ ] the workload demo service starts and shows the expected resource limits
- [ ] timer schedules are visible in `systemctl list-timers --all`

## 4. Logging and observability

- [ ] `journalctl` shows usable logs for managed services
- [ ] log retention is configured
- [ ] evidence logs exist under `/srv/gsx-admin/logs` where expected
- [ ] the main operational runbooks are sufficient to diagnose common failures

## 5. Users, groups, and permissions

- [ ] private developer homes remain private
- [ ] `greendevcorp` shared directories have the expected mode bits and group ownership
- [ ] team login environment is applied through `/etc/profile.d/greendevcorp.sh`
- [ ] PAM or other configured limits are loaded for interactive sessions
- [ ] onboarding and offboarding are documented

## 6. Backup and recovery

- [ ] `/srv/week5-data` is mounted on a filesystem different from `/`
- [ ] the canonical Week 5 runtime config exists at `/etc/gsx-admin/backup-tot.env`
- [ ] at least one recent snapshot exists under `/srv/week5-data/gsx-backups/snapshots`
- [ ] the latest snapshot contains `data/` and `metadata/`
- [ ] `opt/19-verify-backups.sh` succeeds against the latest snapshot
- [ ] restore to an alternate path works before any production overwrite
- [ ] backup and verification logs are reviewable in journald
- [ ] optional offsite copy is configured if the environment supports it

## 7. Documentation and handoff

- [ ] repo-root `README.md` exists and explains the repo structure
- [ ] `docs/README.md` is up to date
- [ ] architecture documentation reflects the final server design
- [ ] the configuration manual is sufficient for a fresh install
- [ ] disaster recovery steps are documented
- [ ] escalation procedure is documented
- [ ] adding a new service is documented
- [ ] recovery test evidence is recorded or ready to be recorded

## 8. Final sign-off commands

Run a final quick pass with:

```bash
systemctl --failed --no-pager
systemctl list-timers --all
sudo journalctl -p err -n 100 --no-pager
sudo bash opt/03-verify.sh
sudo bash opt/07-verify-logging.sh
sudo bash opt/13-verify-resource-limits.sh
sudo bash opt/16-verify-week4-security.sh
sudo bash opt/19-verify-backups.sh
```

