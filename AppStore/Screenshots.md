# BlitzRecorder App Store Screenshots

Source: Apple App Store Connect screenshot specifications and upload guidance.

## Required Sets

- macOS: 16:10 screenshots, currently `2880 x 1800`.
- iPhone 6.9 inch: `1320 x 2868`.
- iPad 13 inch: `2064 x 2752`.

## Capture

```bash
Scripts/capture-app-store-screenshots.sh --all
```

The capture script launches the packaged Mac app in screenshot mode, renders release UI to PNG, builds/runs the iPhone companion in Simulator, and writes PNG files into the App Store screenshot folders.

## Compose (iOS marketing frames)

```bash
swift Scripts/compose-app-store-screenshots.swift
swift Scripts/compose-app-store-screenshots.swift \
  AppStore/ScreenshotAssets/iPad-13/raw AppStore/ScreenshotAssets/iPad-13 2064x2752 ipad
```

Raw captures live in `iPhone-6.9/raw/` and `iPad-13/raw/`. The compositor styles
them with the blitzrecorder.com landing system (ink background, emerald glows,
Schibsted/Hanken type, mint gradient phrase) and frames the real UI in device
bezels. The Mac studio UI (`Web/blitzrecorder/public/generated-screens/macos-recorder-live.png`)
appears in slides 1, 3, and 5 so browsers see the Mac app requirement.

## iOS Slide Story (ASO order)

Captions are keyword-active (Apple indexes screenshot caption text since June
2025) and reinforce the title/subtitle keywords: iphone camera, mac camera,
remote camera, video camera. Headlines stay at 3-6 words, subs one line.

1. `01-hero-mac-iphone` — hook + requirement: Mac + iPhone duo, "iPhone camera for your Mac."
2. `02-pairing` — educate setup: "Pair once with a 6-digit code."
3. `03-mac-control` — educate control: "Camera controls on your Mac." + check items.
4. `04-recording` — differentiator: "Video recording, not a stream."
5. `05-transfer` — close: "Your take lands on your Mac."

## Review

- No private desktop, account, token, or local path data.
- No subscription, StoreKit restore, BlitzReels entitlement, or export quota copy.
- Copy matches `AppStore/Metadata-macOS.md` and `AppStore/Metadata-iOS.md`.
