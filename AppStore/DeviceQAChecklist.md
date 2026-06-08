# BlitzRecorder Device QA Checklist

Use this checklist before uploading App Store builds. It covers workflows that cannot be proven by simulator screenshots or unsigned local builds.

## Direct-Download Access

- Fresh install can record and export 1080p without sign-in.
- Successful exports do not decrement a quota.
- Account panel says the app has a free 1080p tier and Early Lifetime License.
- 1080p export does not require account, card, watermark, or subscription.
- iPhone camera, 4K export, and 60 fps export require an active BlitzRecorder license key.

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
- Cinematic depth recording on supported iPhone hardware records with HEVC, Cinematic video, disparity, metadata, and orientation/mirroring metadata tracks.
- The transfer manifest proves the saved iPhone movie was inspected after recording: `recordedVideoCodecTypes` includes HEVC, `cinematicAssetVerified` is `true`, `cinematicTrackCount` is positive, and `cinematicDurationSeconds` is positive.

Evidence to keep: Mac/iPhone pairing screenshots, the imported source movie, the transfer manifest sidecar when available, and the Cinematic validation output:

```bash
swift Scripts/validate-cinematic-recording.swift path/to/iphone-camera.mov \
  --manifest path/to/transfer-manifest.json \
  --expect-cinematic
```

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
- Direct-download screenshots show release UI and no private data.
- Privacy labels match `AppStore/PrivacyNutritionLabels.md`.

## Commands

```bash
Scripts/validate-launch-readiness.sh
Scripts/validate-storekit-local.sh
Scripts/validate-submission-artifacts.sh
```
