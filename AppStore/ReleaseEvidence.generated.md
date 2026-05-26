# BlitzRecorder Generated Release Evidence

Generated: 2026-05-22 17:54:53 UTC

This report captures command results for the current workspace. Keep this next
to `AppStore/ReleaseEvidence.md` when preparing the final App Store submission.

## Release Identity

- Version/build: `0.1.0 / 1`
- macOS bundle ID: `dev.blitzreels.blitzrecorder`
- iOS companion bundle ID: `dev.blitzreels.blitzrecorder.camera`
- Monthly subscription product ID: `dev.blitzreels.blitzrecorder.pro.monthly`
- Monthly subscription price: `$7.99 per month`
- Annual subscription product ID: `dev.blitzreels.blitzrecorder.pro.annual`
- Annual subscription price: `$49.99 per year`
- Free quota: `3 free exports`

## Command Evidence

### Launch Readiness

- Status: passed
- Log: `build/ReleaseEvidenceLogs/20260522T175453Z-launch-readiness.log`
- Command: `Scripts/validate-launch-readiness.sh`

### App Store Connect Verifier Fixtures

- Status: passed
- Log: `build/ReleaseEvidenceLogs/20260522T175453Z-app-store-connect-fixtures.log`
- Command: `Scripts/test-app-store-connect-readiness.py`

### App Store Connect Bootstrap Fixtures

- Status: passed
- Log: `build/ReleaseEvidenceLogs/20260522T175453Z-app-store-connect-bootstrap-fixtures.log`
- Command: `Scripts/test-app-store-connect-bootstrap.py`

### App Store Connect Dry Run

- Status: passed
- Log: `build/ReleaseEvidenceLogs/20260522T175453Z-app-store-connect-dry-run.log`
- Command: `Scripts/app-store-connect-readiness.py --dry-run`

### StoreKit Local Configuration

- Status: passed
- Log: `build/ReleaseEvidenceLogs/20260522T175453Z-storekit-local.log`
- Command: `Scripts/validate-storekit-local.sh`

### Submission Artifacts

- Status: passed
- Log: `build/ReleaseEvidenceLogs/20260522T175453Z-submission-artifacts.log`
- Command: `Scripts/validate-submission-artifacts.sh`

### Unauthenticated BlitzReels Entitlement Check

- Status: passed
- Log: `build/ReleaseEvidenceLogs/20260522T175453Z-entitlement-unauthenticated.log`
- Command: `Scripts/validate-entitlement-endpoint.sh`

### Local Build/Test Preflight

- Status: passed
- Log: `build/ReleaseEvidenceLogs/20260522T175453Z-local-preflight.log`
- Command: `Scripts/preflight-app-store-local.sh`

### Positive BlitzReels Entitlement Token Check

- Status: pending
- Reason: BLITZRECORDER_ENTITLEMENT_TOKEN is not set
- Log: `build/ReleaseEvidenceLogs/20260522T175453Z-entitlement-token.log`

### Negative BlitzReels Entitlement Token Check

- Status: pending
- Reason: BLITZRECORDER_INACTIVE_ENTITLEMENT_TOKEN is not set
- Log: `build/ReleaseEvidenceLogs/20260522T175453Z-entitlement-inactive-token.log`

### Live App Store Connect Verification

- Status: pending
- Reason: ASC_KEY_ID, ASC_ISSUER_ID, and ASC_PRIVATE_KEY_PATH/ASC_PRIVATE_KEY are not all set
- Log: `build/ReleaseEvidenceLogs/20260522T175453Z-app-store-connect-live.log`

### Strict Submission Artifact Validation

- Status: pending
- Reason: signed App Store archives are not present under build/AppStoreArchives
- Log: `build/ReleaseEvidenceLogs/20260522T175453Z-submission-artifacts-strict.log`

## Remaining Manual Evidence

- Complete `AppStore/AppStoreConnectManualSetup.md` in App Store Connect.
- Complete `AppStore/AppStoreQuestionnaires.md` for age rating, export compliance, content rights, IDFA, Kids Category, and paid-content answers.
- Fill `AppStore/DeviceQAChecklist.md` after physical Mac/iPhone/iPad QA.
- Record legal/privacy approval for terms, privacy policy, and privacy nutrition labels.
- Keep `AppStore/ReleaseEvidence.md` updated with account-side records, signed archive paths, QA evidence, and final submission decision.

## Result

- Local evidence collection completed without command failures.
