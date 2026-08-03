# Onboarding Guide — Adding a New Team Member (Week 4)

This runbook explains how to add a new developer to the GreenDevCorp collaboration model created in Week 4.

---

## 1) Goal

A new developer should:
- have a personal Linux account
- belong to the `greendevcorp` group
- receive a private home directory
- inherit the shared team shell environment automatically on login
- be able to access the shared team workspace, but not other developers’ homes

---

## 2) Standard onboarding procedure

Assume the new user is called `dev5`.

### Create the account

```bash
sudo useradd -m -s /bin/bash dev5
```

### Add the user to the development team group

```bash
sudo usermod -aG greendevcorp dev5
```

### Enforce private home permissions

```bash
sudo chmod 700 /home/dev5
sudo chown dev5:dev5 /home/dev5
```

### Set an initial password if password login is being used locally

```bash
sudo passwd dev5
```

If SSH key-based authentication is used, provision the user’s `~/.ssh/authorized_keys` instead.

---

## 3) What the new user inherits automatically

Because `/etc/profile.d/greendevcorp.sh` is group-scoped, a new login shell for `dev5` should automatically inherit:
- `/home/greendevcorp/bin` in `PATH`
- `umask 0027`
- aliases such as `donelog` and `cdtm`

No per-user `.bashrc` edits are needed.

---

## 4) Validation after onboarding

### Check group membership

```bash
id dev5
```

Expected: `greendevcorp` should appear in the supplementary groups.

### Check private home permissions

```bash
ls -ld /home/dev5
```

Expected: mode `700` and owner `dev5`.

### Check login environment

```bash
sudo runuser -l dev5 -c 'bash -lc "printf \"PATH=%s\\n\" \"$PATH\"; umask"'
sudo runuser -l dev5 -c 'bash -lic "alias donelog"'
```

Expected:
- `PATH` contains `/home/greendevcorp/bin`
- `umask` prints `0027`
- alias `donelog` exists

### Check shared directory access

```bash
sudo runuser -u dev5 -- test -r /home/greendevcorp/done.log && echo ok
sudo runuser -u dev5 -- bash -lc 'touch /home/greendevcorp/shared/dev5-test.txt && ls -l /home/greendevcorp/shared/dev5-test.txt'
```

Expected:
- the log is readable
- the test file inherits group `greendevcorp`

Clean up after the test:

```bash
sudo runuser -u dev5 -- rm -f /home/greendevcorp/shared/dev5-test.txt
```

---

## 5) If the user leaves the team

To revoke shared access without deleting the account immediately:

```bash
sudo gpasswd -d dev5 greendevcorp
```

Then force a new login session for the user if necessary.

If the account should be disabled entirely:

```bash
sudo usermod -L dev5
```

If the account should be removed later:

```bash
sudo userdel -r dev5
```

Be careful not to delete any team-owned or archived work without checking ownership first.

---

## 6) Safer alternative: rerun the managed setup script

If the environment should remain aligned with the scripted policy, rerun the Week 4 setup after user changes:

```bash
sudo GSX_DEV_USERS='dev1 dev2 dev3 dev4 dev5' bash /home/gsx/gsx-admin/opt/15-week4-users-groups-setup.sh
```

This approach helps keep onboarding repeatable and avoids one-off manual drift.

---

## 7) Troubleshooting notes

If the new user cannot access the team area:
- confirm the group membership with `id`
- confirm directory permissions with `ls -ld`
- confirm ACLs with `getfacl`
- make sure the test is done from a **new login shell** so `/etc/profile.d/` and PAM limits are reloaded

For deeper access debugging, see:
- `docs/Runbooks/debug-shared-file-access.md`
