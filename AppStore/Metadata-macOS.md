# BlitzRecorder macOS App Store Metadata

> Paused for direct-download launch. The current macOS product uses Stripe
> license keys and Sparkle, so it should ship as a Developer ID signed DMG, not
> as this Mac App Store listing. Rework this file if/when a StoreKit-based Mac
> App Store build exists.

## App Name

BlitzRecorder

## Bundle ID

`dev.blitzreels.blitzrecorder`

## Subtitle

Mac studio with iPhone camera

## Promotional Text

Record clean creator videos on Mac, then upgrade the direct-download build for iPhone camera, 4K, and 60 fps.

## Description

BlitzRecorder is an open-source Mac recorder for creators who need clean screen, camera, and audio recordings without a heavy production setup.

The free direct-download Mac tier captures your Mac screen, microphone, system audio, and Mac camera into 1080p takes that are ready to export. The paid Early Lifetime License unlocks iPhone camera recording, 4K export, and 60 fps export.

Pair BlitzRecorder Camera on iPhone to use your phone as a remote camera source with live monitor preview, lens selection, zoom, focus, exposure, white balance, stabilization, and torch controls where supported by the device.

The Mac app stays in charge of the take. The iPhone records the master camera file locally, then transfers it back to the Mac so the final export uses the high-quality iPhone recording instead of the monitor preview.

There is no account requirement, watermark, or subscription. The current launch checkout is handled by Stripe on blitzrecorder.com and is not a Mac App Store purchase.

Features:

- Mac screen, camera, microphone, and system audio recording
- Free 1080p screen, Mac camera, microphone, and system audio recording
- Paid iPhone companion camera pairing over the local network
- Live iPhone monitor preview on the Mac
- Remote camera controls for supported iPhone hardware
- Local iPhone master recording with transfer back to the Mac take
- Scene layout and picture-in-picture export
- 4K and 60 fps export with the paid direct-download license
- AGPL source code

Terms: https://blitzrecorder.com/terms
Privacy: https://blitzrecorder.com/privacy

## Keywords

screen recorder,video recorder,iphone camera,mac recording,screen capture,webcam,creator video

## Support URL

https://blitzrecorder.com/support

## Marketing URL

https://blitzrecorder.com

## Privacy Policy URL

https://blitzrecorder.com/privacy

## Review Notes

Do not submit this macOS listing for the current launch. The current macOS build is distributed outside the Mac App Store, validates BlitzRecorder license keys, and uses Sparkle updates.

The iPhone companion app is named BlitzRecorder Camera. It is a separate App Store app that pairs with the Mac app over the local network, shows a 6-digit pairing code, streams monitor preview, accepts camera controls, records the master camera file locally, and transfers the file back to the Mac take.

## In-App Purchases

None for the paused Mac App Store draft. A future Mac App Store build would need StoreKit instead of Stripe license keys.

## Privacy Summary

- Tracking: No
- Local camera and microphone access: Used for recording selected by the user
- Local network: Used for Mac/iPhone pairing, preview, controls, and transfer
- User defaults: Used for app settings and trusted device IDs
- File metadata: Used for app-created recordings and user-selected recording/export locations
- App Store purchases: None in this paused draft
- License checks: Direct-download build validates Stripe-backed BlitzRecorder license keys for iPhone camera, 4K, and 60 fps
