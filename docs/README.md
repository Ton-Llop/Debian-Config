
## Documentation index

### Architecture
- **Architecture / service architecture diagram:**  
  [Service Architecture Diagram](Architecture/Service%20Architecture%20Diagram.md)

### Runbooks
- [restart-service](Runbooks/restart-service.md)
- [check-service-logs](Runbooks/check-service-logs.md)
- [verify-timers](Runbooks/verify-timers.md)
- [restore-backup](Runbooks/restore-backup.md)
- [monitoring-checklist](Runbooks/monitoring-checklist.md)
- [troubleshoot-slow-server](Runbooks/troubleshoot-slow-server.md)
- [troubleshoot-high-cpu](Runbooks/troubleshoot-high-cpu.md)
- [debug-shared-file-access](Runbooks/debug-shared-file-access.md)
- [DisasterRecoveryRunbook](Runbooks/DisasterRecoveryRunbook.md)
- [add-new-service](Runbooks/add-new-service.md)


### Week 1
- [SecurityPolicy](Week1/SecurityPolicy.md)
- [SSHSetupGuide](Week1/SSHSetupGuide.md)
- [Troubleshooting](Week1/Troubleshooting.md)
- [Design Notes](Week1/Design%20Notes.md)

### Week 2
- [Week2 README](Week2/README.md)
- [ServiceManagement](Week2/ServiceManagement.md)
- [LoggingObservability](Week2/LoggingObservability.md)
- [BackupAutomation](Week2/BackupAutomation.md)
- [Design Notes](Week2/Design%20Notes.md)

### Week 3
- [Week3 README](Week3/README.md)
- [ProcessConcepts](Week3/ProcessConcepts.md)
- [DiagnosticsScripts](Week3/DiagnosticsScripts.md)
- [SignalsProcessControl](Week3/SignalsProcessControl.md)
- [ResourceLimits](Week3/ResourceLimits.md)
- [PerformanceBaseline](Week3/PerformanceBaseline.md)
- [Design Notes](Week3/DesignNotes.md)

### Week 4
- [Week4 README](Week4/README.md)
- [UserGroupDesign](Week4/UserGroupDesign.md)
- [PermissionModel](Week4/PermissionModel.md)
- [EnvironmentAndLimits](Week4/EnvironmentAndLimits.md)
- [SecurityVerification](Week4/SecurityVerification.md)
- [OnboardingGuide](Week4/OnboardingGuide.md)
- [Design Notes](Week4/DesignNotes.md)

### Week 5
- [Week5 README](Week5/README.md)
- [DiscMounting](Week5/DiscMounting.md)
- [BackupStrategy](Week5/BackupStrategy.md)
- [AutomatedBackup](Week5/AutomatedBackup.md)
- [BackupVerification](Week5/BackupVerification.md)

### Week 6
- [Week6 README](Week6/README.md)
- [EscalationProcedure](Week6/EscalationProcedure.md)
- [ProductionReadinessChecklist](Week6/ProductionReadinessChecklist.md)
- [RecoveryTestTemplate](Week6/RecoveryTestTemplate.md)
- [RecoveryTestEvidence](Week6/evidence/RecoveryTestEvidence.md)

---

## Conventions

- **Bash scripts must use LF line endings** (avoid CRLF). If you copy files from Windows/shared folders and get `pipefail: invalid option name`, see: [Troubleshooting](Week1/Troubleshooting.md).
- Prefer running setup scripts via `sudo bash …` to avoid `noexec` mount issues on shared folders.
