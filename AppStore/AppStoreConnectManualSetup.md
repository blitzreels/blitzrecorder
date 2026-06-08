# BlitzRecorder App Store Connect Manual Setup

Use this worksheet only after App Store strategy is revisited. The current launch is a direct-download Mac DMG with Stripe license keys and Sparkle updates.

## Records

- macOS app: `dev.blitzreels.blitzrecorder`
- iOS companion app: `dev.blitzreels.blitzrecorder.camera`
- Category: Photo & Video
- Direct-download launch price: free 1080p tier + $39 Early Lifetime License
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
- No account required for 1080p recording/export.
- Direct-download license validation is used for iPhone camera, 4K, and 60 fps.
- Stripe handles purchase history for license purchases.

## QA Before Submission

1. Fresh install the Mac app.
2. Verify 1080p recording/export works without sign-in.
3. Verify the direct-download build is not submitted to the Mac App Store while it uses Stripe license keys or Sparkle.
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
