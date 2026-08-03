# Permission Model Explained (Week 4)

This document explains the Week 4 access-control model in operational terms: who can access what, which Linux permission mechanisms are used, and how to debug problems when access does not behave as expected.

---

## 1) High-level policy

The intended policy is:
- each developer has a private home directory
- all developers can access the shared team area
- only team members can execute team scripts
- files created in the shared directory stay in the team group
- one developer should not be able to delete another developer’s shared files
- all team members can read `done.log`
- only `dev1` can modify `done.log`

This is a least-privilege model: every directory is open only to the exact principals that need it.

---

## 2) Permission map

### `/home/dev1`, `/home/dev2`, `/home/dev3`, `/home/dev4`

Mode:

```text
0700
```

Meaning:
- owner: `rwx`
- group: `---`
- others: `---`

Effect:
- private user homes
- no lateral browsing between developers

---

### `/home/greendevcorp`

Mode:

```text
2750
```

Meaning:
- owner: `rwx` (`root`)
- group: `r-x` (`greendevcorp`)
- others: no access
- special bit `2`: setgid

Effect:
- team members can traverse the team root
- outsiders cannot enter
- new entries created inside inherit the group when appropriate

---

### `/home/greendevcorp/bin`

Mode:

```text
2750
```

The shared helper script `team-env-check` is stored here with mode `0750`.

Effect:
- team members can execute shared scripts
- non-team users cannot execute them
- this supports PATH-based team tooling without making scripts globally executable

---

### `/home/greendevcorp/shared`

Mode:

```text
3770
```

Breakdown:
- `3` = setgid (`2`) + sticky bit (`1`)
- owner/group permissions = `rwx`
- others = `---`

Why both special bits matter:

#### setgid on a directory
When a developer creates a file inside `/home/greendevcorp/shared`, the file inherits the directory’s group:

```text
greendevcorp
```

That means the shared workspace stays group-consistent without the user manually fixing ownership.

#### sticky bit on a directory
Even though the directory is group-writable, users cannot delete each other’s files just because they have write access to the directory.

This matters in a collaboration area because otherwise `dev2` could remove a file created by `dev1`.

The verification script explicitly tests both behaviors.

---

### `/home/greendevcorp/done.log`

Mode:

```text
0640
```

Ownership:
- owner: `dev1`
- group: `greendevcorp`

ACL policy:
- `u:dev1:rw-`
- `g:greendevcorp:r--`
- `o::---`

Effect:
- `dev1` can update the file
- the rest of the team can read it
- outsiders cannot access it

This matches the assignment requirement that all developers can read the task log but only `dev1` can add entries.

---

## 3) Why Unix mode bits alone are not always enough

Classic mode bits can only describe:
- one owner
- one group
- everyone else

That is often enough for shared team directories, but it becomes limiting when one file needs more specific exceptions.

Example from the presentation:
- dev1 and dev2 write
- dev3 read only

That pattern is exactly why POSIX ACLs exist. ACLs let us define per-user and per-group entries beyond the main owner/group split.

---

## 4) ACLs used in this implementation

### ACL on `shared`

The setup applies:

```bash
setfacl -m g:greendevcorp:rwx /home/greendevcorp/shared
setfacl -d -m g:greendevcorp:rwx /home/greendevcorp/shared
```

Meaning:
- the team group has rwx access on the directory
- default ACLs help new files/directories inherit collaborative access behavior

### ACL on `done.log`

The setup applies:

```bash
setfacl -m u:dev1:rw-,g:greendevcorp:r--,o::--- /home/greendevcorp/done.log
```

Meaning:
- one named user has write access
- the team group has read access
- everyone else has none

To inspect the effective ACLs:

```bash
getfacl /home/greendevcorp/shared
getfacl /home/greendevcorp/done.log
```

---

## 5) Common permission questions

### If a file in `/shared` is owned by `dev1`, how can all team members still read it?
Because the directory uses group inheritance and the team group has access. If the file mode or ACL allows group read, every member of `greendevcorp` can read it.

A safe default is:
- owner: read/write
- group: read or read/write depending on collaboration needs
- others: none

The Week 4 shell environment also sets `umask 0027`, which helps prevent world-readable files by default.

### What is the difference between setgid on a directory and on a file?
- on a **directory**, setgid means newly created entries inherit the directory’s group
- on a **file**, setgid means the program executes with the file’s group identity

For collaboration, the directory case is the relevant one. It keeps group ownership stable across shared work.

---

## 6) Manual inspection checklist

To inspect the full model quickly:

```bash
namei -l /home/dev1
namei -l /home/greendevcorp/shared
ls -ld /home/greendevcorp /home/greendevcorp/bin /home/greendevcorp/shared
ls -l /home/greendevcorp/done.log
getfacl /home/greendevcorp/shared
getfacl /home/greendevcorp/done.log
id dev1
id dev2
```

Why `namei -l` is useful:
- it shows permissions on every path component
- many access problems come from a parent directory that blocks traversal

---

## 7) Security trade-offs

What this model does well:
- simple to understand
- easy to automate
- easy to verify
- enforces isolation between homes and collaboration in the team area

What it does not try to solve yet:
- per-project subgroups
- role separation for ops vs contractors
- immutable append-only logs with stronger enforcement than normal write access
- centralized authentication

Those would be the next steps if the server grew beyond the Week 4 scale.
