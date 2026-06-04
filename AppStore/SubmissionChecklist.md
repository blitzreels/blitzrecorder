# BlitzRecorder App Store Submission Checklist

## Product Positioning

- Product name: BlitzRecorder
- Price: free
- In-app purchases: none
- Subscription: none
- Export quota: none
- BlitzReels access: optional external product, not a recorder entitlement gate

## Required Public Pages

Publish these pages to the matching production URLs before App Store submission:

- `https://blitzrecorder.com`
- `https://blitzrecorder.com/privacy`
- `https://blitzrecorder.com/terms`
- `https://blitzrecorder.com/support`

## App Store Connect

Use these files as the source of truth:

- Metadata: `AppStore/Metadata-macOS.md` and `AppStore/Metadata-iOS.md`
- Review notes: `AppStore/ReviewNotes.md`
- Privacy labels: `AppStore/PrivacyNutritionLabels.md`
- Questionnaire answers: `AppStore/AppStoreQuestionnaires.md`
- Machine-readable fields: `AppStore/AppStoreConnectFields.generated.json`

Do not create subscription groups, subscription products, non-consumable purchases, or an export-quota paywall for this release.

## QA

- Fresh install can record and export without sign-in.
- Export does not decrement a quota.
- Export does not show purchase, restore, subscription management, or BlitzReels entitlement UI.
- iPhone companion pairs over the local network and transfers a local camera recording back to the Mac.
- App Store screenshots show the free/open-source account panel, not a plan/paywall panel.

## Commands

```bash
Scripts/validate-launch-readiness.sh
Scripts/validate-storekit-local.sh
Scripts/capture-app-store-screenshots.sh --all
Scripts/validate-submission-artifacts.sh
Scripts/release-status.sh --full
Scripts/collect-release-evidence.sh --full
Scripts/prepare-app-store-review-package.sh
```

Use `Scripts/validate-submission-artifacts.sh --strict` only after public URLs, screenshots, signed archives, and App Store Connect credentials are available.

## Archives

Before each App Store upload, bump both targets together in `project.yml`, then create signed archives through the App Store release workflow or local archive scripts.

Keep account-side records, signed archive paths, QA evidence, and the final submission decision with the private release handoff.
