# Runbook — “A user can’t access a shared file. How do I debug?”

This runbook answers one of the explicit Week 4 documentation prompts: how to troubleshoot when a user cannot access a file they should be able to access.

Goal: determine whether the problem is caused by identity, parent-directory traversal, file mode bits, ACLs, or session state.

---

## 0) Start with the exact symptom

Ask:
- which user is affected?
- what exact path are they trying to access?
- are they trying to **read**, **write**, **execute**, or **delete**?
- is the failure happening in the shared workspace or in a private home directory?
- is the problem in a fresh login session or an old shell?

A user may say “I can’t access the file,” but Linux permissions differ for:
- reading file contents
- traversing directories
- executing a script
- deleting an entry from a directory

---

## 1) Verify identity and group membership

```bash
id <user>
getent group greendevcorp
```

Questions to answer:
- is the user actually in the expected group?
- was the group added recently, requiring a new login session?

If the user was just added to `greendevcorp`, an old session may not reflect the new group membership.

---

## 2) Inspect every path component, not just the file

Use:

```bash
namei -l /home/greendevcorp/shared/somefile
```

Why this matters:
- file access can fail because of a parent directory, not the file itself
- a missing execute bit on one directory blocks traversal even if the file permissions look correct

This is one of the fastest ways to debug Linux path access problems.

---

## 3) Inspect file and directory mode bits

```bash
ls -ld /home/greendevcorp
ls -ld /home/greendevcorp/bin
ls -ld /home/greendevcorp/shared
ls -l /home/greendevcorp/done.log
```

What to compare against in this project:
- private homes: `0700`
- team root/bin: `2750`
- shared dir: `3770`
- done.log: `0640`, owner `dev1`, group `greendevcorp`

---

## 4) Inspect ACLs

If ACLs are used, plain `ls -l` may not tell the whole story.

```bash
getfacl /home/greendevcorp/shared
getfacl /home/greendevcorp/done.log
```

Typical checks:
- does the group ACL match the intended policy?
- does a named user have a more specific entry?
- is the ACL mask restricting permissions more than expected?

If the ACLs look wrong, rerun the managed setup script or reapply the intended ACL entries.

---

## 5) Test as the affected user

Simulate the exact access with `runuser`.

### Read test

```bash
sudo runuser -u <user> -- test -r /path/to/file && echo readable
```

### Write test

```bash
sudo runuser -u <user> -- bash -lc 'echo test >> /path/to/file'
```

### Execute test

```bash
sudo runuser -u <user> -- /path/to/script
```

### Delete test

```bash
sudo runuser -u <user> -- rm -f /path/to/file
```

This avoids guessing. It answers whether the user can really perform the operation.

---

## 6) Special Week 4 cases

### Case A — User cannot access another developer’s home

That is expected.

Home directories are `0700`, so lateral access is intentionally blocked.

### Case B — User cannot execute a script in `/home/greendevcorp/bin`

Check:
- membership in `greendevcorp`
- mode of the script (`0750` expected for `team-env-check`)
- execute permission on parent directories

### Case C — User cannot delete a file in `/home/greendevcorp/shared`

That may also be expected.

The sticky bit on `shared` is there specifically so one team member cannot delete another team member’s file just because the directory is group-writable.

### Case D — User cannot append to `done.log`

Expected unless the user is `dev1`.

That file is intentionally readable by the team but writable only by the authorized writer.

---

## 7) Session-level problems

If the issue is:
- PATH not updated
- alias missing
- PAM limits not visible

then the user may not be in a **new login shell**.

Verify with:

```bash
sudo runuser -l <user> -c 'bash -lc "printf \"PATH=%s\\n\" \"$PATH\"; umask"'
```

If a group was added recently, log out and back in before retesting.

---

## 8) One-command regression check

When in doubt, run the full Week 4 verification:

```bash
sudo bash /home/gsx/gsx-admin/opt/16-verify-week4-security.sh
```

If the environment drifted, rerun setup:

```bash
sudo bash /home/gsx/gsx-admin/opt/15-week4-users-groups-setup.sh
```

Then verify again.
