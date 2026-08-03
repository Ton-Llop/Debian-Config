# Week 4 — Users, Groups & Access Control

Week 4 focuses on building a **secure multi-user collaboration model** for GreenDevCorp. The goal is to let four developers work on the same Debian server without exposing private data, corrupting each other’s files, or exhausting shared resources.

This week implements the requirements from the assignment brief: a shared team group, private home directories, a controlled shared workspace, POSIX ACL usage, PAM-enforced per-user limits, a shared shell environment under `/etc/profile.d/`, and an automated verification script.

---

## Deliverables mapping

### Part A — User & Group Administration

Provisioning script:
- `opt/15-week4-users-groups-setup.sh`

What it creates:
- group `greendevcorp`
- users `dev1`, `dev2`, `dev3`, `dev4`
- private home directories under `/home/<user>` with mode `0700`

### Part B — File Permissions

Shared workspace:
- `/home/greendevcorp/bin`
- `/home/greendevcorp/shared`
- `/home/greendevcorp/done.log`

Permissions model:
- `bin`: team-readable/executable only
- `shared`: setgid + sticky bit (`3770`)
- `done.log`: readable by team, writable only by `dev1`

### Part C — Advanced Access Control

ACL tooling:
- package `acl`
- `setfacl` / `getfacl`

Applied in setup:
- group ACLs on `/home/greendevcorp/shared`
- explicit ACL policy on `done.log`

### Part D — Environment & Shell Config

Tracked shell profile:
- `etc/profile.d/greendevcorp.sh`

Behavior for team members:
- prepends `/home/greendevcorp/bin` to `PATH`
- sets `umask 0027`
- defines common aliases (`ll`, `cdtm`, `donelog`, `teambin`)

### Part E — Security Verification + Documentation

Verification script:
- `opt/16-verify-week4-security.sh`

Documentation:
- `docs/Week4/UserGroupDesign.md`
- `docs/Week4/PermissionModel.md`
- `docs/Week4/EnvironmentAndLimits.md`
- `docs/Week4/SecurityVerification.md`
- `docs/Week4/OnboardingGuide.md`
- `docs/Runbooks/debug-shared-file-access.md`

---

## Quick demo commands

### 1) Apply the Week 4 setup

```bash
sudo bash /home/gsx/gsx-admin/opt/15-week4-users-groups-setup.sh
```

### 2) Verify users, permissions, shell profile, and PAM limits

```bash
sudo bash /home/gsx/gsx-admin/opt/16-verify-week4-security.sh
```

### 3) Inspect the shared workspace manually

```bash
ls -ld /home/greendevcorp
ls -ld /home/greendevcorp/bin
ls -ld /home/greendevcorp/shared
ls -l /home/greendevcorp/done.log
getfacl /home/greendevcorp/shared
getfacl /home/greendevcorp/done.log
```

### 4) Check the inherited login environment for one developer

```bash
sudo runuser -l dev1 -c 'bash -lc "printf \"PATH=%s\\n\" \"$PATH\"; umask; alias"'
```

### 5) Check the PAM limits seen by a login shell

```bash
sudo runuser -l dev1 -c 'bash -lc "ulimit -Sn; ulimit -Hn; ulimit -Su; ulimit -Hu; ulimit -Sv; ulimit -Hv; ulimit -St; ulimit -Ht"'
```

---

## Notes for the oral defense

The core design choices are:
- **group-based collaboration** for normal access
- **private home directories** for user isolation
- **setgid + sticky bit** on the shared directory for safe cooperation
- **ACLs** for finer-grained exceptions beyond basic Unix rwx
- **PAM limits** to stop one user from consuming too many resources
- **`/etc/profile.d/`** for consistent team shell behavior on every new login
- **verification as code** so the security model is tested instead of assumed

These choices line up with the assignment’s least-privilege focus and with the requirement to document both the design and the reasoning behind it.
