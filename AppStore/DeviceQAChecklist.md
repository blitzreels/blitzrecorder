# BlitzRecorder Device QA Checklist

Use this checklist before uploading App Store builds. It covers workflows that cannot be proven by simulator screenshots or unsigned local builds.

## Free Access

- Fresh install can record and export without sign-in.
- Successful exports do not decrement a quota.
- Account panel says the app is free and open source.
- No purchase, restore, subscription management, paywall, or BlitzReels entitlement flow appears.

Evidence to keep: screenshots of the account panel and at least one successful export from a fresh install.

## iPhone Companion

- iPhone and Mac are on the same local network.
- BlitzRecorder Camera shows a 6-digit pairing code.
- Mac app discovers the iPhone camera source.
- Pairing succeeds with the code.
- Monitor preview appears on the Mac.
- Remote camera controls update supported iPhone hardware.
- Starting/stopping from the Mac records a local iPhone camera file.
- Transfer back to Mac completes and the take can export.

## Permissions

- macOS screen recording permission.
- macOS camera permission.
- macOS microphone permission.
- macOS local network permission if prompted.
- iOS camera permission.
- iOS local network permission.
- Optional iOS microphone permission when source camera audio is used.

## App Store Build Checks

- macOS build uses the expected bundle ID.
- iOS build uses the expected companion bundle ID.
- No StoreKit configuration is attached to the Mac run scheme.
- App Store screenshots show release UI and no private data.
- Privacy labels match `AppStore/PrivacyNutritionLabels.md`.

## Commands

```bash
Scripts/validate-launch-readiness.sh
Scripts/validate-storekit-local.sh
Scripts/validate-submission-artifacts.sh
```
