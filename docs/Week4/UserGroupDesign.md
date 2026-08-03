# User/Group Design Rationale (Week 4)

This document explains how the Week 4 user and group model is structured, why it is organized this way, and what trade-offs were made.

---

## 1) Goals and constraints

Week 4 introduces a realistic multi-user server problem:
- developers must collaborate on shared files
- each developer still needs a private workspace
- one user should not be able to browse another user’s home directory
- shared resources need controlled write access
- the system must be testable and explainable

Constraints we assumed:
- Debian base system
- standard Linux user/group model
- no domain controller or LDAP yet
- repeatable setup through Bash automation

---

## 2) Why we created a dedicated development group

We use the Unix group:

```text
greendevcorp
```

This group represents the set of developers who should access the shared Week 4 collaboration area.

Why a dedicated group is useful:
- it maps cleanly to the team described in the scenario
- it lets us grant access once at the directory level instead of per-user everywhere
- it scales better than setting permissions individually on every file
- it keeps the security model readable: “team access” is group access

This is the core of the least-privilege model: users only receive access through the group that reflects their role. They are not given broad global permissions.

---

## 3) Users created for the team

The setup script creates:
- `dev1`
- `dev2`
- `dev3`
- `dev4`

Each user:
- has their own login account
- keeps their own private home directory under `/home/<user>`
- is added to the `greendevcorp` group as a supplementary group

This follows the assignment requirement directly.

---

## 4) Why each developer keeps a private home directory

Each home directory is enforced as:

```text
/home/dev1  -> 0700
/home/dev2  -> 0700
/home/dev3  -> 0700
/home/dev4  -> 0700
```

Why `0700`:
- owner can read, write, and traverse
- no group access
- no access for others

This means:
- users can safely store SSH configs, shell history, personal scripts, and temporary work
- one developer cannot casually inspect another developer’s private files
- mistakes inside the shared team area do not automatically expose home directories

This is an important separation: **private work happens in `/home/<user>`**, **team work happens under `/home/greendevcorp/`**.

---

## 5) Why the shared team workspace is under `/home/greendevcorp`

We created a separate team root:

```text
/home/greendevcorp
```

with three main resources:
- `/home/greendevcorp/bin`
- `/home/greendevcorp/shared`
- `/home/greendevcorp/done.log`

Why keep these outside individual home directories:
- ownership is clearly “team-owned”, not “belongs to one user”
- paths remain stable even if one developer leaves
- permissions can be managed centrally
- documentation and onboarding are simpler because the team path is predictable

---

## 6) Why `dev1` is the only writer of `done.log`

The assignment explicitly says that all developers should be able to read the activity log, but only `dev1` should be able to add new entries.

We therefore made:
- owner: `dev1`
- group: `greendevcorp`
- mode: `0640`
- ACL: `dev1` = read/write, team group = read only

Operational reasoning:
- the file behaves like a lightweight team status ledger
- read access stays broad within the team
- write access is limited to one authorized actor
- accidental edits by the rest of the team are blocked by default

Trade-off:
- this is “single authorized writer”, not true kernel-level append-only semantics
- `dev1` can modify the file, not just append, unless stronger controls such as immutable flags or an application-level append interface are used

---

## 7) Why we still use ACLs even though Unix groups already solve most of the problem

Traditional Unix permissions are ideal for:
- one owner
- one group
- one “others” category

But Week 4 also asks us to use POSIX ACLs for fine-grained access control and to verify them with `getfacl`.

We therefore use ACLs as an extra layer:
- on `shared`, to reinforce group access defaults
- on `done.log`, to make the intended per-user/per-group policy explicit

Why this is useful:
- ACLs document exceptions clearly
- ACLs scale better when future users need different access than the main group
- ACLs let us go beyond the “one owner, one group” limitation of traditional mode bits

---

## 8) Why this design is defendable

This model is intentionally simple:
- private homes for isolation
- one shared group for collaboration
- one shared workspace for common data
- one verification script to prove the model works

That makes it easy to maintain and easy to explain.

If the company later grows to 20 or 100 users, the next step would likely be:
- more role-based groups (`dev`, `ops`, `contractors`, `backup-admins`)
- more ACL exceptions for project-specific directories
- possibly centralized identity management

For the current assignment scale, the chosen design is the smallest model that still satisfies the requirements and the least-privilege principle.
