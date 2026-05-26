# BlitzRecorder Release Evidence

Last updated: 2026-05-22

Use this file as the final submission gate for each App Store release. Replace the placeholders with command output links, screenshots, App Store Connect record IDs, QA initials, or dates before submitting a build for review.

## Release Identity

- Release version: `0.1.0`
- Build number: `1`
- macOS bundle ID: `dev.blitzreels.blitzrecorder`
- iOS companion bundle ID: `dev.blitzreels.blitzrecorder.camera`
- Monthly subscription product ID: `dev.blitzreels.blitzrecorder.pro.monthly`
- Monthly subscription price: `$7.99 per month`
- Annual subscription product ID: `dev.blitzreels.blitzrecorder.pro.annual`
- Annual subscription price: `$49.99 per year`
- Free quota: `3 free exports`

## Local Build Evidence

Required before archive:

```bash
Scripts/preflight-app-store-local.sh
Scripts/validate-launch-readiness.sh
Scripts/test-app-store-connect-readiness.py
Scripts/test-app-store-connect-bootstrap.py
Scripts/app-store-connect-readiness.py --dry-run
Scripts/validate-submission-artifacts.sh
Scripts/collect-release-evidence.sh --full
Scripts/prepare-app-store-review-package.sh
```

Evidence:

Synced from `AppStore/ReleaseEvidence.generated.md` generated 2026-05-22 17:54:53 UTC.

- `Scripts/preflight-app-store-local.sh`: passed (`build/ReleaseEvidenceLogs/20260522T175453Z-local-preflight.log`)
- `Scripts/validate-launch-readiness.sh`: passed (`build/ReleaseEvidenceLogs/20260522T175453Z-launch-readiness.log`)
- `Scripts/test-app-store-connect-readiness.py`: passed (`build/ReleaseEvidenceLogs/20260522T175453Z-app-store-connect-fixtures.log`)
- `Scripts/test-app-store-connect-bootstrap.py`: passed (`build/ReleaseEvidenceLogs/20260522T175453Z-app-store-connect-bootstrap-fixtures.log`)
- `Scripts/app-store-connect-readiness.py --dry-run`: passed (`build/ReleaseEvidenceLogs/20260522T175453Z-app-store-connect-dry-run.log`)
- `Scripts/validate-storekit-local.sh`: passed (`build/ReleaseEvidenceLogs/20260522T175453Z-storekit-local.log`)
- `Scripts/validate-submission-artifacts.sh`: passed (`build/ReleaseEvidenceLogs/20260522T175453Z-submission-artifacts.log`)
- Generated evidence report `AppStore/ReleaseEvidence.generated.md`: generated 2026-05-22 17:54:53 UTC
- Review package manifest: prepared (`build/AppStoreReviewPackage/BlitzRecorder-0.1.0-build-1/Manifest.md`)
- Test count/result: 58 tests, 0 failures (`build/ReleaseEvidenceLogs/20260522T175453Z-local-preflight.log`)

## Public URL Evidence

Required production URLs:

- Landing page: `https://www.blitzreels.com/blitzrecorder`
- Privacy policy: `https://www.blitzreels.com/blitzrecorder/privacy`
- Terms of use: `https://www.blitzreels.com/blitzrecorder/terms`
- Support: `https://www.blitzreels.com/blitzrecorder/support`
- BlitzReels sign-in: `https://www.blitzreels.com/blitzrecorder/sign-in?return_to=blitzrecorder://auth/blitzreels`
- Entitlement endpoint: `https://www.blitzreels.com/api/blitzrecorder/entitlement`

Evidence:

Synced from `build/ReleaseEvidenceLogs/20260522T175453Z-submission-artifacts.log` generated 2026-05-22 17:54:53 UTC.
- Landing page HTTP 200: passed (https://www.blitzreels.com/blitzrecorder returns HTTP 200)
- Privacy policy HTTP 200: passed (https://www.blitzreels.com/blitzrecorder/privacy returns HTTP 200)
- Terms HTTP 200: passed (https://www.blitzreels.com/blitzrecorder/terms returns HTTP 200)
- Support HTTP 200: passed (https://www.blitzreels.com/blitzrecorder/support returns HTTP 200)
- Landing page pricing copy: pending redeploy (https://www.blitzreels.com/blitzrecorder should contain $7.99 per month and $49.99 per year)
- Landing page free quota copy: passed (https://www.blitzreels.com/blitzrecorder contains 3 free exports)
- Landing page BlitzReels copy: passed (https://www.blitzreels.com/blitzrecorder contains eligible BlitzReels subscribers)
- Privacy page Keychain copy: passed (https://www.blitzreels.com/blitzrecorder/privacy contains macOS Keychain)
- Privacy page StoreKit copy: passed (https://www.blitzreels.com/blitzrecorder/privacy contains StoreKit)
- Terms page pricing copy: pending redeploy (https://www.blitzreels.com/blitzrecorder/terms should contain $7.99 per month and $49.99 per year)
- Terms page included access copy: passed (https://www.blitzreels.com/blitzrecorder/terms contains Eligible active BlitzReels subscribers)
- Support page contact copy: passed (https://www.blitzreels.com/blitzrecorder/support contains support@blitzreels.com)
- Unauthenticated sign-in redirects to BlitzReels login: passed (https://www.blitzreels.com/blitzrecorder/sign-in?return_to=blitzrecorder://auth/blitzreels redirects to /login?next=%2Fblitzrecorder%2Fsign-in)
- Invalid sign-in callback returns HTTP 400: passed (https://www.blitzreels.com/blitzrecorder/sign-in?return_to=https://example.com returns HTTP 400)
- Unauthenticated entitlement endpoint returns HTTP 401: passed (https://www.blitzreels.com/api/blitzrecorder/entitlement returns HTTP 401)

## App Store Connect Evidence

Required account-side records:

- App Store Connect setup worksheet completed from `AppStore/AppStoreConnectManualSetup.md`: pending
- App Store questionnaire worksheet completed from `AppStore/AppStoreQuestionnaires.md`: pending
- macOS app record for `dev.blitzreels.blitzrecorder`: pending
- iOS app record for `dev.blitzreels.blitzrecorder.camera`: pending
- macOS App Store version `0.1.0` exists: pending
- iOS App Store version `0.1.0` exists: pending
- macOS app info localization matches name, subtitle, and privacy policy URL: pending
- iOS app info localization matches name, subtitle, and privacy policy URL: pending
- macOS version localization matches description, keywords, promotional text, support URL, and marketing URL: pending
- iOS version localization matches description, keywords, promotional text, support URL, and marketing URL: pending
- macOS uploaded build `1` is `VALID`: pending
- iOS uploaded build `1` is `VALID`: pending
- Subscription group `BlitzRecorder Pro`: pending
- Subscription group en-US display name `BlitzRecorder Pro`: pending
- Monthly subscription product `dev.blitzreels.blitzrecorder.pro.monthly`: pending
- Annual subscription product `dev.blitzreels.blitzrecorder.pro.annual`: pending
- Subscription reference name `BlitzRecorder Pro Monthly`: pending
- Subscription en-US display name `BlitzRecorder Pro`: pending
- Subscription en-US description `Unlimited exports in BlitzRecorder.`: pending
- USA monthly customer price `$7.99`: pending
- USA annual customer price `$49.99`: pending
- Privacy policy URL set on both app records: pending
- Support URL set on both app records: pending
- Review notes copied from `AppStore/ReviewNotes.md`: pending
- Privacy labels copied from `AppStore/PrivacyNutritionLabels.md`: pending

Required verification:

```bash
ASC_KEY_ID=KEY_ID \
ASC_ISSUER_ID=ISSUER_ID \
ASC_PRIVATE_KEY_PATH=/path/to/AuthKey_KEY_ID.p8 \
Scripts/app-store-connect-readiness.py
```

Evidence:

- Live App Store Connect verification result: pending

## Archive Evidence

Required signed archives:

```bash
TEAM_ID=YOUR_TEAM_ID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive-app-store.sh
Scripts/validate-submission-artifacts.sh --strict
```

Evidence:

- macOS archive path: pending
- macOS archive bundle ID/version/build/signing validated: pending
- iOS archive path: pending
- iOS archive bundle ID/version/build/signing validated: pending
- Exported macOS package path: pending
- Exported iOS package path: pending
- Upload result: pending

## Subscription And Entitlement Evidence

Required functional checks:

- Fresh macOS install shows `3` free exports available.
- Three successful exports decrement the free quota.
- Fourth export is blocked until Pro access is active.
- App Store subscription unlocks additional exports.
- Restore purchases restores Pro access.
- BlitzReels sign-in stores the token in the macOS Keychain.
- Eligible BlitzReels subscriber receives included Pro access.
- Ineligible or expired BlitzReels subscriber remains locked after free exports.

Production entitlement verification:

```bash
BLITZRECORDER_ENTITLEMENT_TOKEN=TOKEN Scripts/validate-entitlement-endpoint.sh
BLITZRECORDER_ENTITLEMENT_TOKEN=TOKEN BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE=true Scripts/validate-entitlement-endpoint.sh
BLITZRECORDER_ENTITLEMENT_TOKEN=INACTIVE_TOKEN BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE=false Scripts/validate-entitlement-endpoint.sh
```

Evidence:

- StoreKit local configuration test: passed (`build/ReleaseEvidenceLogs/20260522T175453Z-storekit-local.log`)
- StoreKit sandbox subscription test: pending
- Restore purchases test: pending
- Positive BlitzReels entitlement response with `"active": true`: pending (BLITZRECORDER_ENTITLEMENT_TOKEN is not set)
- Negative BlitzReels entitlement response with `"active": false`: pending (BLITZRECORDER_INACTIVE_ENTITLEMENT_TOKEN is not set)

## Device QA Evidence

Use `AppStore/DeviceQAChecklist.md` for full signoff.

Evidence:

- macOS device/model/version: pending
- iPhone device/model/iOS version: pending
- iPad device/model/iPadOS version: pending
- Camera permission prompt verified: pending
- Local network prompt verified: pending
- Bonjour discovery verified: pending
- Pairing code verified: pending
- Monitor preview verified: pending
- Remote start/stop verified: pending
- Transfer and recovery verified: pending

## Legal And Submission Evidence

Required before submitting to App Review:

- Privacy policy final legal review: pending
- Terms final legal review: pending
- Privacy nutrition labels final review: pending
- Age rating, export compliance, content rights, IDFA, Kids Category, and paid-content questionnaire review: pending
- Support contact monitored: pending
- App Review demo account prepared if included-access path should be tested: pending
- Final screenshot content review: pending

## Final Decision

- Submitter:
- Date:
- App Store Connect build numbers selected:
- Decision: pending
- Notes:
