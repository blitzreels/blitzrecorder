# BlitzRecorder App Store Submission Checklist

## Product Positioning

- Product name: BlitzRecorder
- Direct-download launch: free 1080p tier + $39 Early Lifetime License
- In-app purchases: none for the direct-download launch
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

Do not submit the current macOS direct-download build to the Mac App Store while it uses Stripe license keys and Sparkle. A future Mac App Store release needs a StoreKit model.

## QA

- Fresh install can record and export 1080p without sign-in.
- Export does not decrement a quota.
- 1080p export does not show purchase, restore, subscription management, or BlitzReels entitlement UI.
- iPhone companion pairs over the local network and transfers a local camera recording back to the Mac.
- Direct-download screenshots show the free 1080p tier and Early Lifetime License honestly.

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
