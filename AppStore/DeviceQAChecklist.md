# BlitzRecorder Device QA Checklist

Use this checklist before uploading App Store builds. It covers the workflows that cannot be proven by simulator screenshots or unsigned local builds.

Record each run with:

- Date:
- macOS device and OS:
- iPhone or iPad model and OS:
- BlitzRecorder version/build:
- BlitzRecorder Camera version/build:
- Network type:
- Tester:
- Result: Pass / Fail

## Mac App Subscription And Export Gate

- Fresh install starts with 3 free exports available.
- A short local Mac-only recording can be created and exported.
- Each successful free export decrements the free export count.
- After the third successful free export, starting or exporting another take is blocked by the Pro message.
- App Store sandbox purchase unlocks unlimited exports.
- Restore Purchases restores an active sandbox subscription after reinstall.
- Manage Subscription opens Apple's subscription management destination.
- A cancelled sandbox purchase leaves the app locked after free exports are used.

Evidence to keep: screen recording or screenshots of the Plan popover before export, after 3 exports, and after sandbox subscription/restore.

## BlitzReels Included Access

- Sign in from the Plan popover opens the production BlitzReels sign-in URL.
- The `blitzrecorder://auth/blitzreels` callback returns to the Mac app.
- A reviewer BlitzReels account with an eligible active subscription unlocks Pro.
- An ineligible BlitzReels account stays connected but does not unlock Pro.
- Disconnect BlitzReels removes included access and clears the connection state.
- Reopening the app within the 7-day cache window preserves verified included access.
- A `401` or `403` entitlement response clears stale BlitzReels access.

Evidence to keep: reviewer account email, entitlement endpoint response class, and screenshots of connected eligible/ineligible states. Do not store access tokens in this repo.

## iOS Companion Pairing

- First launch requests camera permission.
- First launch requests local network permission.
- The iOS app displays a 6-digit pairing code.
- The Mac discovers the device over Bonjour on the same local network.
- The Mac does not auto-connect without explicit pairing.
- Entering the correct pairing code connects.
- Entering an incorrect pairing code is rejected.
- The paired iPhone or iPad appears in the Mac camera source picker.
- Previously trusted pairing reconnects without repeating first-time pairing.

Evidence to keep: screenshots of permission prompts, pairing code, Mac source picker, and connected state.

## Remote Camera Recording

- The Mac monitor preview renders frames from the iPhone camera.
- Supported lens controls are visible and unsupported controls are hidden or disabled.
- Zoom, focus, exposure, white balance, stabilization, and torch controls work where supported by the device.
- Starting a Mac recording prepares and starts the iPhone-local recording.
- Stopping from the Mac stops the iPhone recording.
- The iPhone transfers the master recording back to the Mac.
- The final Mac export uses the transferred iPhone camera file.
- Transfer progress is visible during transfer.
- A recording with only the remote iPhone camera enabled can export.
- A recording with screen, microphone, system audio, and remote iPhone camera can export.

Evidence to keep: final exported video, take folder contents, and a screenshot of transfer progress.

## Recovery And Failure Handling

- If the Mac app quits during an iPhone recording, the iPhone does not immediately lose the recording.
- If the local network disconnects during recording, the iPhone preserves the local recording.
- After reconnect, pending iPhone recordings are recoverable or importable.
- If transfer is interrupted, retrying does not corrupt the source recording.
- If disk space is low, the iOS app shows a warning before large recordings.
- If the iPhone hits thermal or storage constraints, the stop reason is visible and media captured so far is preserved.

Evidence to keep: screenshots of pending/recovery state and recovered file paths.

## iOS Companion Scope

- The iOS app does not show a paywall.
- The iOS app does not initiate purchases.
- The iOS app does not behave as a standalone editor.
- The iOS app still presents enough status to stop recording if the Mac disconnects.
- iPhone and iPad layouts both keep important text readable.

Evidence to keep: iPhone and iPad screenshots from real devices when possible.

## App Store Build Checks

- macOS and iOS builds have the same marketing version and build number.
- The iOS build does not include `NSMicrophoneUsageDescription`.
- The iOS build requires camera capability.
- The macOS build includes sandbox, network client, camera, audio input, and user-selected read/write entitlements.
- App icons are opaque and correct size.
- Privacy manifests are bundled in both apps.
- App Store screenshots show release UI and no private data.

Commands to run before signoff:

```bash
Scripts/preflight-app-store-local.sh
Scripts/validate-submission-artifacts.sh
Scripts/app-store-connect-readiness.py --dry-run
```

After signed archives and App Store Connect credentials exist:

```bash
TEAM_ID=YOUR_TEAM_ID ALLOW_PROVISIONING_UPDATES=1 Scripts/archive-app-store.sh
ASC_KEY_ID=KEY_ID ASC_ISSUER_ID=ISSUER_ID ASC_PRIVATE_KEY_PATH=/path/to/AuthKey_KEY_ID.p8 Scripts/app-store-connect-readiness.py
Scripts/validate-submission-artifacts.sh --strict
```
