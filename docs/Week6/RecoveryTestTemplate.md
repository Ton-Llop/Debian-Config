# Recovery Test Evidence

This document is the recording sheet for the **backup restore test**.

It does **not** invent evidence that was not captured. Instead, it defines what should be recorded from the target VM each time a recovery verification is performed.

---

## 1. Where live evidence is generated

The repo already contains the implementation that produces recovery evidence:

- restore verification script: `opt/19-verify-backups.sh`
- manual restore script: `opt/20-restore-backup.sh`
- service unit: `etc/systemd/system/gsx-backup-tot-verify.service`
- timer unit: `etc/systemd/system/gsx-backup-tot-verify.timer`
- verification logs: `/srv/gsx-admin/logs/backups/week5-verify-*.log`
- snapshot manifests under: `/srv/week5-data/gsx-backups/snapshots/<timestamp>/metadata/`

---

## 2. Test record template

Complete one section per recovery test.

### Test metadata

- **Operator:**
- **Date and time (UTC or local):**
- **Host:**
- **Snapshot ID tested:**
- **Restore target path:**
- **Why this test was run:** routine verification / after config change / after incident

### Commands used

```bash
sudo systemctl start gsx-backup-tot-verify.service
sudo journalctl -u gsx-backup-tot-verify.service -n 120 --no-pager
sudo ls -lah /srv/gsx-admin/logs/backups | tail
```

If testing manually instead of through the service:

```bash
sudo bash opt/19-verify-backups.sh
sudo bash opt/20-restore-backup.sh latest /tmp/gsx-restore-test
```

### Expected success criteria

- manifest validation passes for the selected snapshot
- restore to the alternate path completes successfully
- restored file inventory matches the source snapshot
- no production paths are overwritten during the test
- a timestamped verification log is created

### Result summary

- **Manifest check:** pass / fail
- **Restore step:** pass / fail
- **Inventory comparison:** pass / fail
- **Evidence log created:** yes / no
- **Overall result:** pass / fail

### Notes / anomalies

- unexpected warnings:
- files skipped:
- permissions mismatches:
- timing observations:
- follow-up actions required:

---

## 3. Minimal evidence bundle to preserve

At minimum, keep:

- snapshot ID tested
- command output showing pass/fail
- path of the generated verification log
- any anomaly or remediation note

A concise saved summary is enough if it allows another admin to answer:

1. **Which backup was tested?**
2. **Was it restorable?**
3. **Where is the proof?**

---

## 4. Recommended example entry format

```text
Operator: <name>
Date: <timestamp>
Snapshot: <snapshot-id>
Restore target: <path>
Result: PASS
Evidence log: /srv/gsx-admin/logs/backups/week5-verify-<timestamp>.log
Notes: Manifest passed, restore completed, file inventory matched.
```

---

## 5. Handoff note

Before the final handoff, make sure at least one **recent** entry is filled in from the real VM so the documentation includes both:

- the recovery procedure
- proof that the procedure was executed successfully
