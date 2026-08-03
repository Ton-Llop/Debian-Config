# Design Notes (Week 1)

This document captures the rationale behind key **Week 1** technical and security decisions, aligned with the automation scripts (01–04) and the verification workflow.

---

## 1) Why SSH (and why not other remote access options)?

### Why SSH is the default choice
- **Standard + universally available**: SSH is the de-facto remote admin protocol for Linux servers. Every admin toolchain supports it (OpenSSH clients on Linux/macOS/Windows).
- **Strong security model**: supports **public key authentication**, host identity verification (host keys), modern ciphers, and clear hardening knobs (`PasswordAuthentication no`, `PermitRootLogin no`, etc.).
- **Automation-friendly**: easy to script, easy to use with configuration management later, and works cleanly with GitOps-lite workflows (apply config, verify via commands).
- **Least privilege**: works well with a non-root admin account + `sudo`, reducing the need for any persistent “superuser” remote access.

### Why not “password-only SSH”
- Passwords are more exposed to **brute-force** and **credential stuffing**.
- Human risk factors: reuse and phishing.
- Operational noise: constant auth spam on any public-facing endpoint.

### Why not alternatives (Week 1 scope)
- **RDP / GUI remote desktop**: expands attack surface (GUI stack + extra services) and is not aligned with minimal server builds.
- **VNC**: similar issue—extra services, extra exposure; not needed for baseline admin.
- **Telnet**: insecure by design (plaintext).
- **“Only console / VirtualBox UI”**: secure, but not practical for multi-admin workflows and automation. We still treat console access as the break-glass path.

**Week 1 decision:** use SSH as the single remote admin entrypoint, hardened with key-based auth, no root login, and password auth disabled.

---

## 2) Security implications: SSH passwords vs. SSH keys

**Passwords**
- **Higher brute-force risk**: Internet-exposed SSH gets hammered by credential stuffing and brute force. A weak/reused password can fall quickly.
- **Phishing/reuse risk**: Humans reuse passwords; compromise elsewhere can become SSH compromise.
- **Server-side handling**: Even though passwords are hashed, you’re still relying on an authentication factor that can be guessed online.

**Keys (public key auth)**
- **Not guessable in practice**: A properly generated keypair (e.g., Ed25519) is not brute-forced via online guessing the way passwords are.
- **Best practice with passphrase**: If the private key is stolen, a passphrase adds a second barrier (something you have + something you know).
- **Operational benefit**: easier rotation—remove a line from `authorized_keys`; enforce per-user access cleanly.

**Implications for this setup**
- Script 01 disables `PasswordAuthentication` and disables root SSH login, which reduces attack surface.
- The client machine storing the private key becomes critical: use a passphrase and basic endpoint security.

---

## 3) Why this directory structure?

### Design goals
- **Separate “source of truth” from “runtime state”**
- **Make onboarding easier** (new admins can run published scripts without Git access)
- **Enforce least privilege** (group permissions, controlled writable areas)
- **Avoid snowflake servers** (repo-backed config deployment)

### Chosen structure
- **Repo (working copy):** `/home/gsx/gsx-admin`
  - Contains scripts (`opt/`), repo-backed configs (`etc/`), and documentation (`docs/`).
  - This is the **source of truth** for non-secret configuration and automation.
- **Admin filesystem (published runtime):** `/srv/gsx-admin`
  - Created by Script 02.
  - Acts as the operational area: published scripts under `/srv/gsx-admin/opt`, plus admin-owned directories (logs/state/backups).

### Why `/srv/gsx-admin` (and not `/opt` or `/home`)
- `/srv` is a conventional place for **service/admin-managed data** (not ephemeral user data like `/home`).
- Keeps the runtime/admin filesystem independent of a user home directory.
- Makes permissions and group ownership policies clearer (shared admin area).

### Permissions model (high level)
- **Group readable** locations for shared visibility (e.g., docs/config copies).
- **Group writable** locations only where needed (logs/state/backups).
- Use `setgid` on directories so files created inherit the admin group consistently.

**Week 1 decision:** maintain a clear boundary:
- Git repo = versioned “how to configure”
- `/srv/gsx-admin` = operational “where admins operate”

---

## 4) Reinstall scenario: can scripts restore the entire configuration?

**Mostly, but not 100%.** The scripts can re-apply the baseline hardening and structure, but a full “same-machine” restore depends on what was backed up and what secrets/state exist outside the baseline.

**What scripts restore well**
- Package baseline, SSH hardening, unattended upgrades, and repo-backed `/etc` configs (Script 01).
- Admin filesystem layout + permissions + published scripts under `/srv/gsx-admin` (Script 02).
- Sanity checks and orchestration (Script 03).
- Backup of “sensitive-ish” artifacts including `/etc/ssh`, `/etc/sudoers*`, `/etc/hostname`, `/etc/hosts`, `/srv/gsx-admin`, and `/home/gsx/.ssh` (Script 04).

**What may be missing / needs manual decision**
- Secrets not included in the backup list (app tokens, API keys, DB credentials, TLS certs under `/etc/letsencrypt`, etc.).
- Users beyond `gsx` (their home directories and `authorized_keys`) unless explicitly included.
- Firewall rules / network config if not managed in repo and/or not included in backup selection.

**Conclusion**
- Scripts rebuild the baseline reliably.
- Backups help recover key parts of host identity/config.
- Full disaster recovery requires a defined secrets strategy and clear restore steps.

---

## 5) Preventing two team members from running the same setup script concurrently

**Goal:** avoid race conditions and partial/overlapping writes (especially when deploying configs to `/etc` and restarting SSH).

**What we do**
- Use a **global lock** file (e.g., `/var/lock/gsx-week1.lock`) to guarantee mutual exclusion.
- Orchestrator mode (Script 03) sets an environment flag so child scripts don’t deadlock and reuse the lock context.

**Operational rules**
- Prefer running **Script 03 only** as the entrypoint.
- Avoid parallel runs in multiple SSH sessions.
- If a lock is held, scripts should exit with a clear error message.

---

## 6) What should be in Git vs. what should only live on the server (and why)

### Put in Git (versioned, reviewable, reproducible)
- Setup scripts (01–04) and orchestration logic.
- Non-secret configuration templates (repo-backed `/etc` content):
  - SSH hardening config (without private keys)
  - sudoers drop-in policies (policy is not secret)
  - service configs that don’t contain credentials
- Documentation: README, runbooks, troubleshooting, checklists.
- Directory layout definitions and permission policies.

**Why**
- Auditability (who changed what and why).
- Repeatability across reinstalls and new machines.
- Team collaboration via code review.

### Keep only on the server (or in encrypted secret storage), NOT in Git
- Private keys (SSH/TLS), passphrases, API tokens, DB passwords.
- Any `.env` or credential files.
- Machine-specific generated secrets you do not want replicated by default.

**Why**
- Git history is hard to truly purge; a leaked secret is a long-lived incident.
- Least privilege: only admins on the machine should access secrets.
- Reduces blast radius if the repo is exposed.

### Practical Week 1 approach
- Git holds “how to configure” + non-secret configs.
- Server holds secrets; Script 04 backs up selected sensitive-ish artifacts **encrypted**.
- For later weeks: consider a secrets manager or a documented encrypted secrets workflow if full DR is required.

---
