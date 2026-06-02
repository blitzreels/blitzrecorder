# BlitzRecorder App Store Connect Manual Setup

Last updated: 2026-05-22

Use this worksheet while creating the App Store Connect records. The scripts in `Scripts/` verify the finished state, but several App Store Connect choices still require an account owner.

## Shared Release Values

- Release version: `0.1.0`
- Build number: `1`
- Primary language: `English (U.S.)`
- Copyright: `2026 BlitzReels`
- Category: `Photo & Video`
- Marketing URL: `https://www.blitzreels.com/blitzrecorder`
- Support URL: `https://www.blitzreels.com/blitzrecorder/support`
- Privacy Policy URL: `https://www.blitzreels.com/blitzrecorder/privacy`
- Terms URL: `https://www.blitzreels.com/blitzrecorder/terms`
- Standard EULA: Use Apple standard EULA unless a reviewed custom EULA is approved.
- App Store questionnaires: use `AppStore/AppStoreQuestionnaires.md` for age rating, export compliance, content rights, IDFA, Kids Category, and paid-content answers.
- Machine-readable questionnaire answers: use `AppStore/AppStoreQuestionnaireAnswers.generated.json` for exact age rating, export compliance, IDFA, Kids Category, sign-in, and paid-content values.
- Machine-readable field export: use `AppStore/AppStoreConnectFields.generated.json` for exact app record values, screenshot directories, and subscription fields.

## Bundle IDs

Create or confirm these identifiers before app records and signing profiles:

| Target | Bundle ID | Platform | Suggested Name |
| --- | --- | --- | --- |
| macOS app | `dev.blitzreels.blitzrecorder` | macOS | BlitzRecorder |
| iOS companion | `dev.blitzreels.blitzrecorder.camera` | iOS | BlitzRecorder Camera |

The bootstrap script can create missing bundle IDs if API credentials have enough access:

```bash
ASC_KEY_ID=KEY_ID \
ASC_ISSUER_ID=ISSUER_ID \
ASC_PRIVATE_KEY_PATH=/path/to/AuthKey_KEY_ID.p8 \
Scripts/app-store-connect-bootstrap.py --apply
```

## macOS App Record

- Name: `BlitzRecorder`
- Bundle ID: `dev.blitzreels.blitzrecorder`
- SKU: `BLITZRECORDER-MAC`
- Platform: macOS
- Version: `0.1.0`
- Subtitle: copy from `AppStore/Metadata-macOS.md`
- Promotional text: copy from `AppStore/Metadata-macOS.md`
- Description: copy from `AppStore/Metadata-macOS.md`
- Keywords: copy from `AppStore/Metadata-macOS.md`
- Support URL: `https://www.blitzreels.com/blitzrecorder/support`
- Marketing URL: `https://www.blitzreels.com/blitzrecorder`
- Privacy Policy URL: `https://www.blitzreels.com/blitzrecorder/privacy`
- Review notes: copy from `AppStore/ReviewNotes.md`
- Screenshots: use `AppStore/ScreenshotAssets/macOS/`

Important review context:

- The Mac app includes `10 free exports`.
- BlitzRecorder Pro is sold through auto-renewable App Store subscriptions at `$7.99 per month` and `$49.99 per year`.
- Eligible active BlitzReels subscribers can unlock included Pro access by signing in from the Plan popover.
- The iOS app is a companion app and should be reviewed with the Mac app when possible.

## iOS Companion App Record

- Name: `BlitzRecorder Camera`
- Bundle ID: `dev.blitzreels.blitzrecorder.camera`
- SKU: `BLITZRECORDER-CAMERA-IOS`
- Platform: iOS
- Version: `0.1.0`
- Subtitle: copy from `AppStore/Metadata-iOS.md`
- Promotional text: copy from `AppStore/Metadata-iOS.md`
- Description: copy from `AppStore/Metadata-iOS.md`
- Keywords: copy from `AppStore/Metadata-iOS.md`
- Support URL: `https://www.blitzreels.com/blitzrecorder/support`
- Marketing URL: `https://www.blitzreels.com/blitzrecorder`
- Privacy Policy URL: `https://www.blitzreels.com/blitzrecorder/privacy`
- Review notes: copy from `AppStore/ReviewNotes.md`
- iPhone screenshots: use `AppStore/ScreenshotAssets/iPhone-6.9/`
- iPad screenshots: use `AppStore/ScreenshotAssets/iPad-13/`

Important review context:

- The iOS app does not function as a standalone recorder.
- The iOS app does not include a paywall or initiate purchases.
- Pairing requires BlitzRecorder on Mac, the same local network, and the six-digit pairing code shown on the iPhone.
- The iOS target declares camera and local network usage, but not microphone usage.

## Subscription Setup

Create the subscription under the macOS app record.

- Subscription group reference name: `BlitzRecorder Pro`
- Subscription group display name: `BlitzRecorder Pro`
- Monthly subscription product reference name: `BlitzRecorder Pro Monthly`
- Monthly subscription product ID: `dev.blitzreels.blitzrecorder.pro.monthly`
- Annual subscription product reference name: `BlitzRecorder Pro Annual`
- Annual subscription product ID: `dev.blitzreels.blitzrecorder.pro.annual`
- Type: Auto-renewable subscription
- Durations: 1 month and 1 year
- Prices: `$7.99 per month` and `$49.99 per year`
- USA customer prices: `$7.99` and `$49.99`
- Display name: `BlitzRecorder Pro`
- Description: `Unlimited exports in BlitzRecorder.`

Subscription review notes:

- The subscription unlocks unlimited Mac exports/renders after the `10 free exports` are used.
- Purchase, restore, and subscription management are handled in the macOS app through StoreKit.
- The iOS companion app does not sell or restore the subscription.
- BlitzReels included access is a separate entitlement path for eligible active BlitzReels subscribers and does not bill through the iOS companion.

The bootstrap script can create the subscription group/product/localizations after the Mac app record exists. Pricing still requires account-owner confirmation in App Store Connect:

```bash
ASC_KEY_ID=KEY_ID \
ASC_ISSUER_ID=ISSUER_ID \
ASC_PRIVATE_KEY_PATH=/path/to/AuthKey_KEY_ID.p8 \
Scripts/app-store-connect-bootstrap.py --apply
```

## Privacy Labels

Use `AppStore/PrivacyNutritionLabels.md` as the worksheet.
Use `AppStore/PrivacyNutritionLabels.generated.json` as the machine-readable export for exact privacy-label values.
Use `AppStore/AppStoreQuestionnaires.md` for the related age-rating, export-compliance, content-rights, IDFA, Kids Category, and paid-content questions.

Mac app:

- Tracking: No
- Conditional data linked to user: Identifiers / User ID for BlitzReels sign-in access token
- Purpose: App Functionality
- Purchases handled by Apple StoreKit
- Recordings stored locally by default

iOS companion:

- Tracking: No
- Data collected: No
- Camera and local network are used for companion functionality
- Microphone is not requested

Confirm final labels in App Store Connect with legal/privacy review before submission.

## Reviewer Access

If App Review should test BlitzReels included access, add a reviewer account with an active eligible BlitzReels subscription in the App Review notes.

Minimum reviewer instructions:

1. Install BlitzRecorder on Mac.
2. Install BlitzRecorder Camera on iPhone or iPad.
3. Use both devices on the same local network.
4. Pair using the six-digit code shown by the iOS app.
5. Verify the Mac app allows `10 free exports`.
6. Use StoreKit sandbox to test subscription purchase and restore.
7. Optional: sign in with the provided BlitzReels account from the Mac Plan popover to verify included access.

## Signing And Upload

After both app records, bundle IDs, signing certificates, and profiles exist:

```bash
TEAM_ID=YOUR_TEAM_ID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive-app-store.sh
```

To create local App Store export packages for strict validation:

```bash
TEAM_ID=YOUR_TEAM_ID ALLOW_PROVISIONING_UPDATES=1 EXPORT=1 Scripts/archive-app-store.sh
```

To upload after archive/export validation:

```bash
TEAM_ID=YOUR_TEAM_ID ALLOW_PROVISIONING_UPDATES=1 UPLOAD=1 Scripts/archive-app-store.sh
```

Validate the finished submission package:

```bash
ASC_KEY_ID=KEY_ID \
ASC_ISSUER_ID=ISSUER_ID \
ASC_PRIVATE_KEY_PATH=/path/to/AuthKey_KEY_ID.p8 \
Scripts/app-store-connect-readiness.py

Scripts/validate-submission-artifacts.sh --strict
```

The live App Store Connect check verifies registered bundle IDs, app records, App Store version `0.1.0`, app info localization, version localization copied from `AppStore/AppStoreConnectFields.generated.json`, uploaded build `1` in `VALID` processing state for both apps, the subscription group/product, en-US subscription names/descriptions, and USA subscription price. Strict validation checks the signed `.xcarchive` bundles, export option plists, local macOS `.pkg`, local iOS `.ipa`, public URLs, screenshots, and live App Store Connect records. Regenerate export options with the real `TEAM_ID`; dry-run placeholder `ABCDE12345` is intentionally rejected by the strict gate.

## Final Handoff

Before submitting for review, run:

```bash
Scripts/release-status.sh --full
Scripts/collect-release-evidence.sh --full
```

Generated release evidence is written under `build/`. Keep account-side records, signed archive paths, QA evidence, and the final submission decision with the private release handoff.

Do not submit until:

- Live App Store Connect verification passed.
- Signed macOS and iOS archives exist and pass strict validation.
- Positive production BlitzReels entitlement token test passed.
- Physical Mac/iPhone/iPad QA passed.
- Privacy policy, terms, and privacy nutrition labels received final review.
