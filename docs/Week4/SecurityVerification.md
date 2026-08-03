# Security Verification & Testing (Week 4)

Week 4 is not complete just because users and directories exist. It requires a verification script that proves users can access what they should, cannot access what they should not, and that PAM limits are actually enforced.

This document explains what `opt/16-verify-week4-security.sh` checks and how to use it as evidence.

---

## 1) Verification philosophy

We treat access control as something to **test**, not something to assume.

A correct Week 4 implementation should prove all of the following:
- the group and users exist
- home directories are private
- shared directories are accessible to the team
- outsiders are blocked
- setgid and sticky bit behavior actually works
- `done.log` follows the intended read/write policy
- login sessions inherit PATH, aliases, and PAM limits
- at least one active test shows a configured limit being enforced

This approach also supports the assignment’s broader emphasis on documentation, validation, and defensible operational decisions.

---

## 2) How to run the verification

```bash
sudo bash /home/gsx/gsx-admin/opt/16-verify-week4-security.sh
```

Expected behavior:
- the script prints `PASS`, `FAIL`, and `SKIP` lines
- a final summary is printed at the end
- the script exits with non-zero status if any check fails

This makes it usable as both a manual validation tool and a quick regression check after changes.

---

## 3) What the verification script checks

### Group and users

It verifies:
- group `greendevcorp` exists
- users `dev1`, `dev2`, `dev3`, `dev4` exist
- each developer is a member of the team group

### Home directory privacy

It checks that each home directory:
- exists
- is owned by the correct user
- has mode `700`

It also performs a negative test showing that one developer cannot traverse another developer’s home directory.

### Shared workspace existence and permissions

It confirms:
- `/home/greendevcorp/bin` exists
- `/home/greendevcorp/shared` exists
- `/home/greendevcorp/done.log` exists
- `/home/greendevcorp/shared` has mode `3770`

### Team bin execution policy

It verifies:
- `dev1` can execute `team-env-check`
- a non-team user cannot execute that shared script

### Shared directory collaboration behavior

It creates a temporary file in `/home/greendevcorp/shared` and verifies:
- the file inherits group `greendevcorp`
- another team member can read it
- another team member cannot delete it because the sticky bit blocks that action

### `done.log` authorization

It checks:
- a team member can read the log
- `dev2` cannot append
- `dev1` can append successfully

### Session inheritance

It verifies via login shells that:
- `PATH` contains `/home/greendevcorp/bin`
- the `donelog` alias exists in interactive login shells

### PAM limits

It compares the configured values in `limits.conf` with the runtime values returned by `ulimit` in a `dev1` login session.

### Active enforcement probe

It performs an open-file descriptor probe to demonstrate that the `nofile` limit is not only configured, but actually enforced.

---

## 4) Manual spot checks

The script is the primary verification artifact, but manual checks are useful during debugging.

### Identity and group membership

```bash
getent group greendevcorp
id dev1
id dev2
```

### Path traversal and permissions

```bash
namei -l /home/dev1
namei -l /home/greendevcorp/shared
ls -ld /home/greendevcorp/bin /home/greendevcorp/shared
ls -l /home/greendevcorp/done.log
```

### ACL visibility

```bash
getfacl /home/greendevcorp/shared
getfacl /home/greendevcorp/done.log
```

### Login environment

```bash
sudo runuser -l dev1 -c 'bash -lc "printf \"PATH=%s\\n\" \"$PATH\"; umask"'
sudo runuser -l dev1 -c 'bash -lic "alias donelog"'
```

### PAM limits at runtime

```bash
sudo runuser -l dev1 -c 'bash -lc "ulimit -Sn; ulimit -Hn; ulimit -Su; ulimit -Hu; ulimit -Sv; ulimit -Hv; ulimit -St; ulimit -Ht"'
```

---

## 5) What would count as evidence for the professor

Good Week 4 evidence includes:
- output of `16-verify-week4-security.sh`
- `ls -ld` showing directory modes
- `getfacl` output showing ACL entries
- `id devX` output showing group membership
- `runuser -l devX` output showing inherited PATH and aliases
- `ulimit` output in a login shell showing limits inherited from PAM

The best evidence is behavioral evidence:
- user cannot delete another user’s shared file
- outsider cannot execute team bin scripts
- unauthorized writer cannot append to `done.log`

That is stronger than screenshots of static configuration alone.

---

## 6) Failure interpretation

If a test fails, typical causes are:
- user not added to the correct group
- directory mode missing setgid or sticky bit
- ACL package not installed or ACL not applied
- `/etc/profile.d/greendevcorp.sh` not loaded because the shell was not a new login shell
- `pam_limits.so` missing from `/etc/pam.d/common-session`
- mismatch between expected repo config and live system state

When in doubt, rerun setup first:

```bash
sudo bash /home/gsx/gsx-admin/opt/15-week4-users-groups-setup.sh
```

Then rerun verification.
