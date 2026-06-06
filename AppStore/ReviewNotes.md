# BlitzRecorder App Review Notes

Use this as the source for App Store Connect review notes only after App Store
strategy is revisited. The current launch is a direct-download Mac DMG with
Stripe license keys and Sparkle updates.

## macOS App

App name: BlitzRecorder
Bundle ID: `dev.blitzreels.blitzrecorder`

Do not submit the current macOS direct-download build to App Store review. It records the Mac screen, Mac camera, microphone, and system audio in the free 1080p tier, then uses a Stripe-backed Early Lifetime License to unlock iPhone camera, 4K export, and 60 fps export.

Review path:

1. Launch BlitzRecorder on macOS.
2. Grant screen, camera, microphone, and system audio permissions when prompted.
3. Create or record a short take.
4. Export the take.
5. Confirm 1080p export does not require sign-in, subscription restore, or an account.

## iOS Companion App

App name: BlitzRecorder Camera
Bundle ID: `dev.blitzreels.blitzrecorder.camera`

BlitzRecorder Camera is not a standalone recorder or video editor. It is a companion camera app for BlitzRecorder on Mac. It pairs with the Mac app over the local network, displays a 6-digit pairing code, provides a live monitor feed, accepts camera controls from the Mac, records the master camera file locally, and transfers that recording back to the Mac take.

Review path:

1. Install BlitzRecorder Camera on an iPhone or iPad.
2. Connect the iPhone or iPad and the Mac to the same local network.
3. Open BlitzRecorder Camera and grant camera and local network access.
4. Open BlitzRecorder on Mac and choose the iPhone camera source.
5. Enter the 6-digit pairing code shown on the iPhone or iPad.
6. Verify monitor preview, start/stop camera recording from the Mac, and transfer back to the Mac take.

The iOS companion app does not initiate purchases and does not include a paywall.

## Public URLs

- Marketing: `https://blitzrecorder.com`
- Privacy: `https://blitzrecorder.com/privacy`
- Terms: `https://blitzrecorder.com/terms`
- Support: `https://blitzrecorder.com/support`

## Notes

- Recordings are stored locally by default.
- The iOS app requires camera access and local network access.
- The iOS app declares microphone permission for optional source camera audio.
- The direct-download Mac app does not use StoreKit or BlitzReels entitlement checks. It validates BlitzRecorder license keys for iPhone camera, 4K, and 60 fps.
