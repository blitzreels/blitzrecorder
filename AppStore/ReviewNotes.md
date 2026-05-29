# BlitzRecorder App Review Notes

Use this as the source for App Store Connect review notes for the macOS app and the iOS companion app.

## macOS App

App name: BlitzRecorder
Bundle ID: `dev.blitzreels.blitzrecorder`

BlitzRecorder is a Mac recording studio. It records the Mac screen, camera, microphone, and system audio, then exports the finished take. New users can complete 3 free exports. After the free exports are used, additional exports require BlitzRecorder Pro through the App Store subscription products `dev.blitzreels.blitzrecorder.pro.monthly` or `dev.blitzreels.blitzrecorder.pro.annual`.

Subscriptions should be configured as BlitzRecorder Pro at $7.99 per month and $49.99 per year in the BlitzRecorder Pro subscription group.

Review path:

1. Launch BlitzRecorder on macOS.
2. Grant screen, camera, microphone, and system audio permissions when prompted.
3. Create or record a short take.
4. Export up to 3 times without subscribing.
5. After the free export allowance is used, open the Plan popover and verify that Pro is required for additional exports.
6. Use the App Store sandbox subscription flow to verify restore/purchase behavior.

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

The iOS companion app does not initiate purchases and does not include a paywall. Subscription purchase and restore are handled in the macOS app.

## BlitzReels Included Access

Eligible active BlitzReels subscribers can unlock BlitzRecorder Pro in the Mac app by signing in from the Plan popover. The app opens:

`https://www.blitzreels.com/blitzrecorder/sign-in?return_to=blitzrecorder://auth/blitzreels`

If the reviewer is not already signed in to BlitzReels, the page redirects to BlitzReels login and then returns to the BlitzRecorder sign-in route. After sign-in, the app receives a callback token, stores it in the macOS Keychain, and verifies access at:

`https://www.blitzreels.com/api/blitzrecorder/entitlement`

For App Review, provide a BlitzReels reviewer account with an active eligible subscription in App Store Connect if reviewers should test the included-access path. The App Store subscription path can be reviewed without a BlitzReels account.

## Public URLs

- Marketing: `https://www.blitzreels.com/blitzrecorder`
- Privacy: `https://www.blitzreels.com/blitzrecorder/privacy`
- Terms: `https://www.blitzreels.com/blitzrecorder/terms`
- Support: `https://www.blitzreels.com/blitzrecorder/support`

## Notes

- Recordings are stored locally by default.
- The iOS app requires camera access and local network access.
- The iOS app declares microphone permission for optional source camera audio.
- The Mac app uses StoreKit for subscription status.
- BlitzReels entitlement tokens are stored in the macOS Keychain.
