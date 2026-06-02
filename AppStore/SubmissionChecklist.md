# BlitzRecorder App Store Submission Checklist

Last updated: 2026-05-22

## Product Positioning

- Product name: BlitzRecorder
- Companion app name: BlitzRecorder Camera
- Bundle IDs:
  - macOS: `dev.blitzreels.blitzrecorder`
  - iOS companion: `dev.blitzreels.blitzrecorder.camera`
- Monthly subscription product ID: `dev.blitzreels.blitzrecorder.pro.monthly`
- Monthly price: $7.99 per month
- Annual subscription product ID: `dev.blitzreels.blitzrecorder.pro.annual`
- Annual price: $49.99 per year
- Trial behavior: 10 free exports, then Pro required for additional exports
- BlitzReels access: active eligible BlitzReels subscribers can unlock Pro by signing in

## Public URLs

Publish these pages to the matching production URLs before App Store submission:

- Landing page: `https://www.blitzreels.com/blitzrecorder`
- Privacy policy: `https://www.blitzreels.com/blitzrecorder/privacy`
- Terms of use: `https://www.blitzreels.com/blitzrecorder/terms`
- Support: `https://www.blitzreels.com/blitzrecorder/support`

Canonical source files live in `Web/blitzrecorder/`.

## App Store Connect

Use `AppStore/AppStoreConnectManualSetup.md` as the field-by-field setup worksheet for app records, subscription configuration, privacy labels, reviewer notes, signing, and final verification.
Use `AppStore/AppStoreQuestionnaires.md` for age rating, export compliance, content rights, IDFA, Kids Category, and paid-content questionnaire answers.
Use `AppStore/AppStoreQuestionnaireAnswers.generated.json` as the exact machine-readable questionnaire export.
Use `AppStore/AppStoreConnectFields.generated.json` as the exact machine-readable field export for app records, screenshot folders, and subscription values.

- Create the macOS app record for `dev.blitzreels.blitzrecorder`.
- Create the iOS companion app record for `dev.blitzreels.blitzrecorder.camera`.
- Create auto-renewable subscriptions:
  - Monthly product ID: `dev.blitzreels.blitzrecorder.pro.monthly`
  - Monthly display price: $7.99/month
  - Annual product ID: `dev.blitzreels.blitzrecorder.pro.annual`
  - Annual display price: $49.99/year
  - Subscription group: BlitzRecorder Pro
  - Benefit: unlimited exports/renders in BlitzRecorder
- Add privacy policy URL to both app records.
- Add support URL to both app records.
- Use Apple standard EULA unless a reviewed custom EULA is published.
- Add review notes explaining:
  - The Mac app has 10 free exports.
  - Additional exports require the App Store subscription or a BlitzReels entitlement.
  - The iOS app is a companion remote camera and does not function as a standalone recorder.
  - Pairing requires both devices on the same local network and a six-digit code shown on the iPhone.

Use `AppStore/ReviewNotes.md` as the source for App Store Connect review notes. Before submission, add a BlitzReels reviewer account with an active eligible subscription if App Review should test the included-access path.

Local StoreKit testing is configured in `AppStore/BlitzRecorder.storekit` and wired into the `BlitzRecorder` run scheme. Keep the local product IDs, App Store Connect product IDs, and `ProductConfiguration` StoreKit IDs identical. Run `Scripts/validate-storekit-local.sh` before sandbox purchase QA to verify the StoreKit config, scheme wiring, purchase/restore code paths, and Plan popover controls are still aligned.

BlitzReels included-access verification is defined in `AppStore/BlitzReelsEntitlementContract.md`. Before review, the production endpoint must pass:

```bash
Scripts/validate-entitlement-endpoint.sh
BLITZRECORDER_ENTITLEMENT_TOKEN=TOKEN Scripts/validate-entitlement-endpoint.sh
BLITZRECORDER_ENTITLEMENT_TOKEN=TOKEN BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE=true Scripts/validate-entitlement-endpoint.sh
BLITZRECORDER_ENTITLEMENT_TOKEN=INACTIVE_TOKEN BLITZRECORDER_ENTITLEMENT_EXPECTED_ACTIVE=false Scripts/validate-entitlement-endpoint.sh
Scripts/validate-submission-artifacts.sh
```

After creating the App Store Connect records and subscription, verify the live Apple-side setup with a read-only API check:

```bash
ASC_KEY_ID=KEY_ID \
ASC_ISSUER_ID=ISSUER_ID \
ASC_PRIVATE_KEY_PATH=/path/to/AuthKey_KEY_ID.p8 \
Scripts/app-store-connect-readiness.py
```

The live check verifies both app records, App Store version `0.1.0`, app info localization, version localization copied from `AppStore/AppStoreConnectFields.generated.json`, uploaded build `1` in `VALID` processing state for both targets, the subscription group/products, en-US subscription names/descriptions, and the USA `$7.99` monthly and `$49.99` annual subscription prices.

To reduce manual setup, create the API-manageable resources first. This registers missing bundle IDs and, once the Mac app record exists, creates the `BlitzRecorder Pro` subscription group, monthly and annual subscription products, and en-US localizations. It does not create app records or pricing; those remain App Store Connect account-owner steps.

```bash
Scripts/app-store-connect-bootstrap.py
ASC_KEY_ID=KEY_ID \
ASC_ISSUER_ID=ISSUER_ID \
ASC_PRIVATE_KEY_PATH=/path/to/AuthKey_KEY_ID.p8 \
Scripts/app-store-connect-bootstrap.py --apply
```

Without App Store Connect credentials, the same script can still validate local expected bundle and product IDs:

```bash
Scripts/test-app-store-connect-readiness.py
Scripts/test-app-store-connect-bootstrap.py
Scripts/app-store-connect-readiness.py --dry-run
```

## App Store Archives

Before each App Store upload, bump both targets together in `project.yml`:

- `MARKETING_VERSION`: user-facing release version, for example `0.1.0`
- `CURRENT_PROJECT_VERSION`: monotonically increasing build number, for example `1`

The macOS and iOS companion targets must ship with the same version/build pair. `Scripts/preflight-app-store-local.sh` and `Scripts/validate-submission-artifacts.sh` validate the built values.

Archive both deliverables from the shared project after the App Store Connect records, bundle IDs, signing certificates, and provisioning profiles exist:

```bash
TEAM_ID=YOUR_TEAM_ID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive-app-store.sh
```

Useful variants:

```bash
TEAM_ID=YOUR_TEAM_ID TARGET=mac Scripts/archive-app-store.sh
TEAM_ID=YOUR_TEAM_ID TARGET=ios Scripts/archive-app-store.sh
TEAM_ID=YOUR_TEAM_ID EXPORT=1 Scripts/archive-app-store.sh
TEAM_ID=YOUR_TEAM_ID UPLOAD=1 Scripts/archive-app-store.sh
```

Archives are written to `build/AppStoreArchives/`. Exported App Store packages are written to `build/AppStoreExports/`. The strict submission validator checks both export option plists, rejects the placeholder dry-run team ID `ABCDE12345`, and requires a macOS `.pkg` plus an iOS `.ipa` when you are validating a local export package.

`Scripts/archive-app-store.sh` runs the local preflight before archiving unless `SKIP_PREFLIGHT=1` is set, validates archived bundle IDs, and verifies that archived apps are signed with an App Store distribution identity. Use `EXPORT=1` to create local packages for strict artifact validation, then use `UPLOAD=1` when you are ready to upload through Xcode. Use `DRY_RUN=1` to print the archive/export commands without invoking Xcode:

```bash
TEAM_ID=YOUR_TEAM_ID DRY_RUN=1 UPLOAD=1 Scripts/archive-app-store.sh
```

## Privacy Nutrition Labels

Confirm final labels with counsel and App Store Connect before submission. Current implementation indicates:

- Recordings are stored locally by default.
- Local network data is used for iPhone pairing, monitor preview, camera controls, and file transfer.
- StoreKit handles App Store subscription state.
- BlitzReels sign-in stores its access token in the macOS Keychain and sends it to the BlitzReels entitlement endpoint only while verifying included access.
- Support requests may include user-provided contact details and attachments.
- Privacy manifests are bundled for both apps:
  - Mac: `Sources/BlitzRecorderApp/PrivacyInfo.xcprivacy`
  - iPhone companion: `Apps/iOSCamera/Resources/PrivacyInfo.xcprivacy`
- Required-reason API declarations cover current `UserDefaults`, file metadata, and iPhone disk-space checks. Keychain use does not require a privacy manifest reason.
- Use `AppStore/PrivacyNutritionLabels.md` as the App Store Connect privacy-label worksheet.
- Use `AppStore/PrivacyNutritionLabels.generated.json` as the exact machine-readable privacy-label export.

## Metadata

Use the platform-specific App Store Connect copy:

- macOS: `AppStore/Metadata-macOS.md`
- iOS companion: `AppStore/Metadata-iOS.md`
- Index/shared details: `AppStore/Metadata.md`
- Machine-readable App Store Connect fields: `AppStore/AppStoreConnectFields.generated.json`
- Screenshot plan: `AppStore/Screenshots.md`
- Review notes: `AppStore/ReviewNotes.md`
- Device QA: `AppStore/DeviceQAChecklist.md`
- Privacy labels: `AppStore/PrivacyNutritionLabels.md`
- Machine-readable privacy labels: `AppStore/PrivacyNutritionLabels.generated.json`
- App Store Connect setup: `AppStore/AppStoreConnectManualSetup.md`
- App Store questionnaires: `AppStore/AppStoreQuestionnaires.md`
- Machine-readable questionnaire answers: `AppStore/AppStoreQuestionnaireAnswers.generated.json`

Confirm final screenshots, keywords, subscription wording, and review notes before upload.

Capture screenshot assets into the validated upload folders:

```bash
Scripts/capture-app-store-screenshots.sh --all
```

Run the launch artifact consistency check before each submission build:

```bash
Scripts/validate-launch-readiness.sh
```

For a submission go/no-go view, run the release status summary and keep generated evidence local under `build/`:

```bash
Scripts/release-status.sh --full
Scripts/collect-release-evidence.sh --full
```

Run the local StoreKit configuration check before sandbox subscription QA:

```bash
Scripts/validate-storekit-local.sh
```

Run the submission artifact check while preparing upload assets. Without `--strict`, it reports missing final artifacts as pending; with `--strict`, it fails until public URLs, screenshots, signed archives, and live App Store Connect records are all verifiable:

```bash
Scripts/validate-submission-artifacts.sh
Scripts/validate-submission-artifacts.sh --strict
```

For a fuller local preflight that also builds both targets and checks bundle resources:

```bash
Scripts/preflight-app-store-local.sh
```

For the submission go/no-go view, run the release status summary and fill the evidence worksheet before selecting builds in App Store Connect:

```bash
Scripts/release-status.sh --full
```

Generate a Markdown evidence report from the current workspace and command outputs:

```bash
Scripts/collect-release-evidence.sh --full
```

Prepare a local handoff folder for App Store Connect upload/paste work. This copies metadata, screenshots, public web source, worksheets, and evidence into `build/AppStoreReviewPackage/` with a checksum manifest:

```bash
Scripts/prepare-app-store-review-package.sh
```

## macOS Build Gates

Run before uploading:

```bash
swift test
xcodebuild -project BlitzRecorder.xcodeproj -scheme BlitzRecorder -configuration Release -destination 'platform=macOS' build
```

For direct Developer ID distribution outside the Mac App Store, also notarize. The local packaged app can be checked with:

```bash
Scripts/package-app.sh
codesign -dvvv --entitlements :- build/BlitzRecorder.app
spctl -a -vv build/BlitzRecorder.app
```

`spctl` will reject a Developer ID build until it has been notarized.

## iOS Companion Build Gates

Run before uploading:

```bash
xcodebuild -project BlitzRecorder.xcodeproj -target BlitzRecorderCamera -configuration Release -sdk iphoneos build
```

Verify on a physical iPhone:

- Camera permission prompt appears and camera preview starts.
- Local network prompt appears.
- Mac discovers the phone over Bonjour.
- Pairing code is required on first connection.
- Monitor preview renders on the Mac.
- Start, stop, and transfer complete for a real recording.
- Unsupported camera controls are hidden or disabled.

Use `AppStore/DeviceQAChecklist.md` for full physical-device signoff, including subscription/export gating, BlitzReels included access, pairing, remote camera recording, transfer recovery, and App Store build checks.

## Current Known Gaps

- Real-device Mac+iPhone end-to-end pairing, recording, and transfer still needs manual verification.
- Production BlitzReels entitlement endpoint is deployed and unauthenticated requests return HTTP 401. A signed-in eligible BlitzReels subscriber token still needs one real production positive check returning `{ "active": true, "planName": "..." }`.
- App Store subscription must be created in App Store Connect before StoreKit can load the real product.
- App Store Connect API-manageable setup can be started with `Scripts/app-store-connect-bootstrap.py --apply`, but app records and subscription pricing still require App Store Connect account-owner completion.
- App Store Connect live record verification requires `Scripts/app-store-connect-readiness.py` with API credentials after the macOS app, iOS companion app, version records, localized metadata, uploaded builds, subscription group, subscriptions, and $7.99 monthly / $49.99 annual USA prices are created.
- Current App Store screenshot PNGs exist and pass dimension checks in `AppStore/ScreenshotAssets/`; review final content manually against the real release workflow before upload.
- Final signed App Store archives still need to be created in `build/AppStoreArchives/` with `TEAM_ID=... ALLOW_PROVISIONING_UPDATES=1 Scripts/archive-app-store.sh`.
- Direct Developer ID distribution requires notarization; the current packaged app is signed but not notarized.
- Legal copy is published at `https://www.blitzreels.com/blitzrecorder/privacy` and `https://www.blitzreels.com/blitzrecorder/terms`, but should still receive final legal review before App Store submission.
