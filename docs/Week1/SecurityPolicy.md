# Security Policy (Week 1)

This document defines the baseline security rules for the **GSX Week 1** Debian server build.  
It is intended to be **practical and enforceable**, aligned with the automated setup scripts and verification.

---

## 1. Purpose

- Reduce the attack surface of a fresh Debian server.
- Enforce strong authentication and least privilege.
- Ensure timely patching of security updates.
- Provide clear operational rules for admins and collaborators.

---

## 2. Scope

Applies to:

- The **Week 1** Debian server(s) managed by this repo.
- All users with administrative access (members of `gsx-admin`).
- All configuration and automation tracked in the repository.

Future updates during the following weeks.

---

## 3. Roles and responsibilities

### 3.1 `root`
- Direct remote login is **disabled**.
- Used only via local console access or via `sudo` escalation from an admin account.

### 3.2 Admin users (`gsx-admin`)
- Human administrators (e.g., `gsx`, future collaborators).
- Must use key-based SSH.
- Must follow change-control rules in this repository.

### 3.3 Non-admin users
- Must not have `sudo` privileges unless explicitly approved and documented.

---

## 4. Account and access control

### 4.1 Principle of least privilege
- Admin privileges are granted **only** through the `gsx-admin` group.
- Avoid adding users to `sudo` directly; manage via group membership.

### 4.2 Group-based sudo policy
- `gsx-admin` is the single admin group for privileged access.
- Sudo is enabled via a drop-in policy under `/etc/sudoers.d/` (preferred) rather than editing `/etc/sudoers` directly.
- Any sudoers change must pass:
  ```bash
  sudo visudo -c
  ```

### 4.3 Administrative access approval
- Adding a new admin requires:
  - documented purpose (in docs or change log),
  - SSH public key added,
  - membership in `gsx-admin`,
  - confirmation that password auth is not relied upon.

---

## 5. Authentication policy

### 5.1 SSH authentication
- **Key-based authentication is required** for admin access.
- Password authentication is disabled (or explicitly planned to be disabled as part of hardening).

### 5.2 Password policy (local)
- Passwords must not be shared.
- Strong passwords are required for local console access (even if SSH passwords are disabled).

### 5.3 Key management
- Preferred key types: `ed25519` (or `rsa` ≥ 3072 if needed).
- Private keys must be protected with a passphrase whenever feasible.
- If a key is suspected compromised, remove it from `authorized_keys` immediately and rotate.

---

## 6. SSH hardening rules

### 6.1 Root login
- `PermitRootLogin no`

### 6.2 Password authentication
- `PasswordAuthentication no` (target state)

### 6.3 Non-default SSH port
- SSH listens on a hardened port (e.g., **2222**) as an additional noise-reduction control.
- Note: port changes do **not** replace proper authentication.

### 6.4 Configuration management
- SSH configuration changes must be validated before restart:
  ```bash
  sudo sshd -t && sudo systemctl restart ssh
  ```

### 6.5 Client-side verification
- Admins must verify they can connect using the expected port and key before logging out of console access.

---

## 7. Patch management

### 7.1 Automatic security updates
- Automatic installation of security updates must be enabled (e.g., `unattended-upgrades`).
- Timers/services must be enabled and running.

### 7.2 Manual maintenance window
- Admins should periodically run:
  ```bash
  sudo apt-get update
  sudo apt-get upgrade
  ```
  to apply non-security updates in controlled windows (as the project evolves).

---

## 8. Logging and audit

### 8.1 Baseline
- System logs are accessible via `journalctl`.
- SSH and auth-related logs must be checked during troubleshooting.

### 8.2 Minimum expectation
- Investigate repeated failed SSH attempts.
- Review logs after any hardening change or failed verification.

---

## 9. Backups and recovery (Week 1 baseline)

- Backups are stored under `var/backup/` (if/when used).
- Before applying risky config changes, create a snapshot/backup of relevant files:
  - `/etc/ssh/sshd_config`
  - `/etc/sudoers.d/*`
  - unattended-upgrades configuration

---

## 10. Change control (GitOps-lite)

All configuration and scripts should be tracked in Git.

Rules:

- Changes must be committed with meaningful messages.
- The repo structure should remain consistent (`docs/`, `etc/`, `opt/`, `var/backup/`).
- Avoid manual “snowflake” changes on servers; prefer updating the repo and re-applying.

---

## 11. Incident response (minimal process)

If a compromise is suspected:

1. **Regain control** (console access if needed).
2. **Rotate credentials** (remove keys, reset passwords).
3. **Collect evidence** (relevant `journalctl` logs).
4. **Rebuild from known-good** (preferred over unknown state).
5. Document what happened and what changed.

---

## 12. Review and updates

- This policy is reviewed whenever Week 1 requirements change (e.g., SSH port, authentication method).
- Any deviations must be documented (with rationale) in the repo.
