# Environment Personalization & PAM Limits (Week 4)

Week 4 asks for two user-session controls beyond plain directory permissions:
- a shared team shell environment for new logins
- per-user limits for CPU, memory, processes, and open files enforced through PAM

This document explains both parts and why they matter.

---

## 1) Shared shell environment in `/etc/profile.d/`

The setup script installs:

```text
/etc/profile.d/greendevcorp.sh
```

The presentation explicitly asks for a shared shell configuration in `/etc/profile.d/`, aliases, PATH customization, and proof that a new login inherits the correct environment.

### Why `/etc/profile.d/` was chosen

Benefits:
- central place for team-wide shell settings
- no need to manually edit each user’s `~/.bashrc`
- consistent behavior for every new team member
- version-controlled in the repo under `etc/profile.d/`

This is better than copying personal shell config into each account because it keeps the environment reproducible.

---

## 2) What the profile script changes

The profile file only activates for users who belong to `greendevcorp`.

### PATH customization

It prepends:

```text
/home/greendevcorp/bin
```

to the login shell `PATH`.

Effect:
- team members can run shared helper commands directly
- for example, `team-env-check` can be executed without typing the full path

The script also avoids duplicate PATH entries by checking whether the directory is already present.

---

### `umask 0027`

This sets safer default permissions for newly created files and directories.

For a new regular file:
- base mode starts from `666`
- subtract `027`
- effective default becomes `640`

For a new directory:
- base mode starts from `777`
- subtract `027`
- effective default becomes `750`

Why this is useful:
- files are not world-readable by default
- directories are not open to unrelated users
- team collaboration still works in the shared directory because that directory has its own group/ACL design

Important nuance:
- `umask` affects **newly created** files only
- it does not retroactively change existing permissions
- directory mode bits and ACLs still matter

---

### Common aliases

The team profile defines:

```bash
alias ll='ls -alF --color=auto'
alias cdtm='cd /home/greendevcorp/shared'
alias donelog='tail -n 20 /home/greendevcorp/done.log'
alias teambin='ls -l /home/greendevcorp/bin'
```

Why these aliases exist:
- `ll` gives a richer file listing
- `cdtm` gives a fast shortcut to the collaboration directory
- `donelog` makes the shared task log easy to inspect
- `teambin` shows shared team commands

These are convenience features, not security controls.

---

## 3) How the environment is verified

The verification script checks two session-level behaviors:
- login shells inherit `/home/greendevcorp/bin` in `PATH`
- interactive login shells expose the `donelog` alias

Example manual test:

```bash
sudo runuser -l dev4 -c 'bash -lc "printf \"PATH=%s\\n\" \"$PATH\""'
sudo runuser -l dev4 -c 'bash -lic "alias donelog"'
```

A new login session is required after the setup because `/etc/profile.d/` is applied during shell initialization.

---

## 4) PAM-based per-user limits

The setup updates:

```text
/etc/security/limits.conf
```

and ensures PAM loads:

```text
pam_limits.so
```

This is how the per-user limits are inherited by login sessions.

### Limits configured for `@greendevcorp`

```text
soft nofile 128
hard nofile 256
soft nproc  64
hard nproc  128
soft as     524288
hard as     786432
soft cpu    10
hard cpu    15
```

Meaning:
- `nofile`: max open file descriptors
- `nproc`: max number of processes
- `as`: max virtual address space in KB
- `cpu`: max CPU time in minutes

---

## 5) Why PAM limits were used instead of shell-only `ulimit`

A plain `ulimit` command in one shell is not a complete solution because:
- it may apply only to that shell session
- it is easy to forget
- it does not create a shared system policy

Using `/etc/security/limits.conf` plus `pam_limits.so` gives us:
- a central configuration file
- automatic inheritance on new logins
- reproducible behavior across users in the same group


---

## 6) How the script verifies PAM inheritance

The verification script logs in as `dev1` and checks:
- `ulimit -Sn` / `-Hn`
- `ulimit -Su` / `-Hu`
- `ulimit -Sv` / `-Hv`
- `ulimit -St` / `-Ht`

It compares those runtime values against the expected policy in `/etc/security/limits.conf`.

It also includes an active open-file probe that repeatedly opens descriptors until the configured limit is reached. That turns the limit from “configured text” into observable behavior.

---

## 7) Trade-offs and future improvement

Current design strengths:
- simple, central, version-controlled
- automatically inherited on login
- easy to verify in the oral interview

Possible future improvements:
- move Week 4 policy to a dedicated `/etc/security/limits.d/greendevcorp.conf`
- split different resource policies for developers vs contractors
- add shell prompt customization or shared functions if the team grows
- use centrally managed dotfiles if per-role environments become more complex
