# Design Notes (Week 4)

This document explains **what we implemented in Week 4**, **why we designed it this way**, and gives explicit answers to the Week 4 questions from the assignment.

---

## 1) Goals and constraints

Week 4 asks us to design a collaborative Linux environment where multiple developers can:

- have private personal spaces
- share team resources safely
- avoid interfering with each other’s work
- operate under a least-privilege access model
- inherit a consistent shell environment
- be constrained by reasonable per-user login limits

Our design goals were therefore:

1. keep the model simple enough to explain in an interview
2. use standard Debian/Linux mechanisms first
3. make the setup idempotent and scriptable
4. verify the policy with positive and negative tests, not only by inspection

---

## 2) What we implemented

Main implementation files:

- `opt/15-week4-users-groups-setup.sh`
- `opt/16-verify-week4-security.sh`
- `etc/profile.d/greendevcorp.sh`
- `etc/security/limits.conf`

### User/group model

We created:

- group `greendevcorp`
- users `dev1`, `dev2`, `dev3`, `dev4`

Each developer has:

- their own Unix account
- a private home directory under `/home/<user>`
- membership in the shared team group `greendevcorp`

We kept the model intentionally small:

- **private work** stays in each user’s home directory
- **team collaboration** happens through the shared workspace owned by the team group

This separates personal data from team data and makes the permission model easier to reason about.

### Shared team workspace

We created the shared team area under:

- `/home/greendevcorp/bin`
- `/home/greendevcorp/shared`
- `/home/greendevcorp/done.log`

#### `/home/greendevcorp/bin`
Purpose:
- shared scripts and helper commands for team members only

Why this design:
- keeps team tools in one predictable path
- easy to add to every developer’s `PATH`
- easy to restrict so outsiders cannot execute team-only helpers

#### `/home/greendevcorp/shared`
Purpose:
- collaborative working directory for team files

Configured with:
- owner `root`
- group `greendevcorp`
- mode `3770`

This means:
- group members can read/write/enter the directory
- **setgid** ensures new files inherit group `greendevcorp`
- **sticky bit** prevents one developer from deleting another developer’s files just because the directory is shared
- others have no access

This is a good least-privilege compromise: collaboration is allowed, but destructive actions are limited.

#### `/home/greendevcorp/done.log`
Purpose:
- simple team activity log of completed tasks

Required policy:
- readable by all team members
- writable only by one authorized user

We implemented that as:
- owner: `dev1`
- group: `greendevcorp`
- mode: `0640`
- ACL enforcing `dev1` write, team read-only

Why:
- it matches the assignment exactly
- it demonstrates that not every shared file should be group-writable
- it shows how ACLs can express a policy more precisely than “just chmod 660 everywhere”

### Environment personalization

We installed a shared shell file in:

- `/etc/profile.d/greendevcorp.sh`

It does the following for members of `greendevcorp`:

- prepends `/home/greendevcorp/bin` to `PATH`
- sets `umask 0027`
- provides common aliases such as `ll`, `cdtm`, `donelog`, `teambin`

Why `/etc/profile.d/` instead of editing each user’s `.bashrc` manually?

- centralized administration
- new team members inherit the same environment automatically
- less drift between accounts
- idempotent and easier to track in Git

### Resource limits with PAM

We configured login-session limits for `@greendevcorp` in `/etc/security/limits.conf`:

- `nofile` (max open file descriptors)
- `nproc` (max processes)
- `as` (address-space limit)
- `cpu` (CPU time limit)

We also ensure `pam_limits.so` is loaded in the PAM session stack.

Why login limits here?

- Week 4 explicitly asks for per-user CPU and memory limits plus file/process limits
- PAM limits are a standard way to apply these restrictions to interactive login sessions
- they protect the machine from accidental abuse such as opening too many files or spawning too many processes

Trade-off:
- PAM limits apply to PAM-managed sessions, not to all system services. For services, systemd cgroups are usually the better tool. That is why this complements Week 3 rather than replacing it.

---

## 3) Why this design instead of other possible models

### Why one shared Unix group?
We used **one primary collaboration group** (`greendevcorp`) because the whole Week 4 scenario describes one development team working together.

Benefits:
- simple membership model
- easy to explain and audit with `id`, `groups`, `getent group`
- easy group-based permissions on shared directories

Alternative:
- separate groups per subproject or per role

Why we did not start with that:
- unnecessary complexity for four developers and one shared workspace
- harder to document and verify for the current assignment scope

### Why traditional permissions plus ACLs?
Traditional permissions are the base model because they are:
- simple
- standard
- visible immediately with `ls -l`

We added ACLs only where they improved precision:
- explicit team rwx defaults on the shared directory
- explicit “dev1 writes, team reads” on `done.log`

This is a deliberate balance:
- not ACLs everywhere
- not chmod-only everywhere
- use the more advanced tool only where the policy actually needs it

### Why root owns the shared team directories?
We set the shared workspace directories to be owned by `root` with group `greendevcorp`.

Why:
- developers collaborate through group permissions, not by owning the directory itself
- avoids one developer accidentally changing ownership or broad directory policy
- makes the administrative boundary clearer

---

## 4) Security model summary

Our intended policy is:

- each developer has a private home directory (`0700`)
- only team members can use `/home/greendevcorp/bin`
- only team members can access `/home/greendevcorp/shared`
- files created in the shared directory stay in group `greendevcorp`
- a developer cannot delete another developer’s file from the shared directory just because it is group-writable
- all team members can read `done.log`
- only `dev1` can append/write to `done.log`
- all team members get the same shared login environment
- resource limits are inherited on login through PAM

This is least privilege because each area grants only what is necessary:
- privacy where data is personal
- collaboration where data is shared
- restricted write access where integrity matters

---

## 5) Verification strategy

We did not want to trust the setup “just because the script ran”.

That is why `opt/16-verify-week4-security.sh` performs both:

- **positive tests**: something allowed should work
- **negative tests**: something forbidden should fail

Examples included in verification:

- user exists / user belongs to `greendevcorp`
- home directory is owned by the correct user and is mode `700`
- team members can execute scripts in `/home/greendevcorp/bin`
- outsiders cannot execute the same team script
- files created in `/home/greendevcorp/shared` inherit group `greendevcorp`
- `dev2` can read a shared file created by `dev1`
- `dev2` cannot delete that file because of sticky bit
- `dev2` can read `done.log`
- `dev2` cannot append to `done.log`
- `dev1` can append to `done.log`
- login shells inherit the custom `PATH` and aliases
- PAM limits are inherited and the open-file ceiling is actively probed

This is important for the interview because we can show not only the design, but also evidence that it behaves as intended.

---

## 6) Required questions from the assignment (explicit answers)

### Q1) If a file is in a shared directory and owned by `dev1`, but needs to be readable by all team members, what permissions would you set? Why?
The clean answer is:

- make sure the file group is `greendevcorp`
- set the mode to at least `0640` if only the owner should write
- use `0660` if the whole group should also write

In our Week 4 design, files created inside `/home/greendevcorp/shared` inherit group `greendevcorp` because of **setgid on the directory**. That means a file owned by `dev1` can still be readable by all team members through the group permission bits.

So:
- **`0640`** = owner read/write, group read, others none
- **`0660`** = owner read/write, group read/write, others none

Which one we choose depends on whether the file should be collaborative or protected from group modification.

### Q2) What’s the difference between setgid on a directory vs. a file? Why would you use each?
**setgid on a directory**:
- new files and subdirectories created inside inherit the directory’s group
- this is very useful for collaborative workspaces
- we use it on `/home/greendevcorp/shared` so all files stay in group `greendevcorp`

**setgid on a file**:
- when the file is executed, it runs with the file’s group privileges
- this can be useful in special cases, but it is more security-sensitive
- we do **not** use it in this week because it is unnecessary for our collaboration model and would add avoidable risk/complexity

So the key point is:
- on directories, setgid is mainly a **group inheritance** tool
- on executable files, setgid is a **privilege behavior** tool

### Q3) If you misconfigure permissions and a user can’t access a file they need, how do you troubleshoot? What tools would you use?
We troubleshoot from the outside in:

1. **Confirm the identity of the user**
   ```bash
   id dev2
   groups dev2
   ```

2. **Check every directory in the path**
   A file may be correct, but an upper directory may block traversal.
   ```bash
   namei -l /home/greendevcorp/shared/somefile
   ```

3. **Inspect classic ownership and mode bits**
   ```bash
   ls -ld /home/greendevcorp /home/greendevcorp/shared
   ls -l /home/greendevcorp/shared/somefile
   ```

4. **Inspect ACLs**
   ```bash
   getfacl /home/greendevcorp/shared/somefile
   ```

5. **Test as the affected user**
   ```bash
   sudo -u dev2 test -r /home/greendevcorp/shared/somefile && echo ok
   sudo -u dev2 test -w /home/greendevcorp/shared/somefile && echo ok
   ```

6. **Check whether the session needs renewal**
   If group membership or `/etc/profile.d/` changed, the user may need a new login session.

This avoids guessing and lets us pinpoint whether the problem is:
- wrong owner
- wrong group
- wrong mode bits
- missing execute bit on a directory
- ACL override
- stale login session

### Q4) How would you verify that your permission model actually enforces the security policy you intended?
We verify it with **behavioral tests**, not only by reading `ls -l` output.

Examples:
- allowed action should succeed:
  - `dev2` can read a shared file
  - `dev1` can append to `done.log`
- forbidden action should fail:
  - outsider cannot execute team bin script
  - `dev2` cannot delete `dev1`’s file in sticky shared dir
  - `dev2` cannot append to `done.log`

That is exactly why we wrote `opt/16-verify-week4-security.sh`.

In other words, the security policy is verified by **attempting real accesses** and checking whether Linux allows or denies them as expected.

---

## 7) Operational trade-offs

### Strengths of this design
- simple to explain and audit
- uses standard Linux mechanisms
- idempotent setup script
- explicit verification script
- supports collaboration without making everything world-readable or fully group-writable

### Limitations
- one shared group is fine for 4 users, but may be too coarse for larger teams
- `done.log` authorization is intentionally simple and would not scale well to many approvers/editors
- PAM limits are coarse safety rails, not full workload management
- there is no centralized identity system yet (LDAP/SSSD/AD)

### What we would improve for a larger environment
If the company grew from 4 developers to 20 or 100, we would likely:
- split access by teams/projects instead of one flat group
- use dedicated shared project directories
- move from local accounts to centralized identity
- add sudo policy per role
- add quota/storage controls and auditing
- use configuration management for user lifecycle at scale

---

## 8) Final rationale

The key idea behind our Week 4 design is:

- **private homes for privacy**
- **one shared team workspace for collaboration**
- **special bits and ACLs to express the exact policy**
- **PAM limits to protect the machine from accidental abuse**
- **verification tests to prove the model works**

This fits the assignment well because it is:
- functional
- reasonably secure
- reproducible
