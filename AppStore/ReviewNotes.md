# BlitzRecorder App Review Notes

Use this as the source for App Store Connect review notes for the macOS app and the iOS companion app.

## macOS App

App name: BlitzRecorder
Bundle ID: `dev.blitzreels.blitzrecorder`

BlitzRecorder is a free, open-source Mac recording studio. It records the Mac screen, camera, microphone, and system audio, then exports the finished take. There is no Pro tier, export limit, watermark, account requirement, in-app purchase, subscription, or BlitzReels entitlement gate.

Review path:

1. Launch BlitzRecorder on macOS.
2. Grant screen, camera, microphone, and system audio permissions when prompted.
3. Create or record a short take.
4. Export the take.
5. Confirm export does not require purchase, sign-in, subscription restore, or an account.

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
- The Mac app does not use StoreKit or BlitzReels entitlement checks to unlock recording or export.
