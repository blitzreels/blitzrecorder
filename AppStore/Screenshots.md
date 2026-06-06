# BlitzRecorder App Store Screenshots

Source: Apple App Store Connect screenshot specifications and upload guidance.

## Required Sets

- macOS: 16:10 screenshots, currently `2880 x 1800`.
- iPhone 6.9 inch: `1260 x 2736`.
- iPad 13 inch: `2064 x 2752`.

## Capture

```bash
Scripts/capture-app-store-screenshots.sh --all
```

The capture script launches the packaged Mac app in screenshot mode, renders release UI to PNG, builds/runs the iPhone companion in Simulator, and writes PNG files into the App Store screenshot folders.

## Required Scenes

1. Mac recorder workspace with screen/camera/audio setup.
2. Account panel showing the free 1080p tier, Early Lifetime License, and no subscription controls.
3. iPhone companion pairing and live camera workflow.

## Review

- No private desktop, account, token, or local path data.
- No subscription, StoreKit restore, BlitzReels entitlement, or export quota copy.
- Copy matches `AppStore/Metadata-macOS.md` and `AppStore/Metadata-iOS.md`.
