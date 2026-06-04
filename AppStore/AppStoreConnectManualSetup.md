# BlitzRecorder App Store Connect Manual Setup

Use this worksheet while creating the App Store Connect records. BlitzRecorder is free and open source for this release.

## Records

- macOS app: `dev.blitzreels.blitzrecorder`
- iOS companion app: `dev.blitzreels.blitzrecorder.camera`
- Category: Photo & Video
- Price: free
- In-app purchases: none
- Subscriptions: none

## Metadata

Copy from:

- `AppStore/Metadata-macOS.md`
- `AppStore/Metadata-iOS.md`
- `AppStore/ReviewNotes.md`
- `AppStore/AppStoreConnectFields.generated.json`

## Privacy

Use:

- `AppStore/PrivacyNutritionLabels.md`
- `AppStore/PrivacyNutritionLabels.generated.json`
- `AppStore/AppStoreQuestionnaires.md`
- `AppStore/AppStoreQuestionnaireAnswers.generated.json`

Current model:

- No tracking.
- No analytics SDK.
- No crash reporting SDK.
- No account or entitlement check required to record/export.
- No purchase history collected by BlitzRecorder.

## QA Before Submission

1. Fresh install the Mac app.
2. Verify recording/export works without sign-in.
3. Verify there is no purchase, restore, subscription management, export quota, or BlitzReels entitlement prompt.
4. Pair BlitzRecorder Camera over the local network.
5. Verify iPhone monitor preview, remote camera controls, local iPhone recording, transfer, and Mac export.

## Final Checks

```bash
Scripts/validate-launch-readiness.sh
Scripts/validate-storekit-local.sh
Scripts/release-status.sh --full
Scripts/collect-release-evidence.sh --full
```

Do not add subscription products in App Store Connect unless the product model changes again.
