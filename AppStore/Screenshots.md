# BlitzRecorder Screenshot Plan

Source: Apple App Store Connect screenshot specifications and upload guidance.

## Required Counts

- Upload 1 to 10 screenshots per platform.
- Use `.png`, `.jpg`, or `.jpeg`.
- App previews are optional.
- Store final upload assets in:
  - `AppStore/ScreenshotAssets/macOS/`
  - `AppStore/ScreenshotAssets/iPhone-6.9/`
  - `AppStore/ScreenshotAssets/iPad-13/`
- Validate final screenshot dimensions with:

```bash
Scripts/capture-app-store-screenshots.sh --all
Scripts/validate-submission-artifacts.sh --strict
```

Capture modes:

```bash
Scripts/capture-app-store-screenshots.sh --mac
Scripts/capture-app-store-screenshots.sh --iphone
Scripts/capture-app-store-screenshots.sh --ipad
```

The capture script launches the packaged Mac app in screenshot mode, asks the app to render its real content view to PNG, builds/runs the iPhone companion in Simulator, creates a 13-inch iPad simulator if needed, and writes PNG files into the upload folders above. Review the screenshots manually before upload; final App Store screenshots should show the real release workflow and no private desktop/account data.

## macOS

Required for the Mac app record.

Use 16:10 screenshots. Accepted sizes include:

- 1280 x 800
- 1440 x 900
- 2560 x 1600
- 2880 x 1800

Recommended set:

1. Main recording canvas with screen and camera layers visible.
2. Plan popover showing 3 free exports, $4.99/month Pro, Restore, Terms, Privacy, and Support.
3. Remote iPhone camera controls showing connected companion capabilities.
4. Export/render completed state with a finished take.
5. Scene layout controls showing picture-in-picture or stacked layout.

The local capture script currently writes the first three macOS screenshots:

- `01-main-recording-canvas.png`
- `02-plan-popover.png`
- `03-iphone-camera-controls.png`

## iOS

Required for the BlitzRecorder Camera app record. Since the companion target supports iPhone and iPad, prepare both iPhone and iPad screenshots unless the App Store Connect record is changed to iPhone-only.

Minimum practical upload set:

- iPhone 6.9-inch portrait: 1260 x 2736, 1290 x 2796, or 1320 x 2868.
- iPad 13-inch portrait: 2064 x 2752 or 2048 x 2732.

Recommended iPhone set:

1. Pairing screen showing the 6-digit code.
2. Connected camera preview.
3. Connected state while Mac controls are available.
4. Recording state.
5. Transfer complete state.

Recommended iPad set:

1. Pairing screen.
2. Connected preview.
3. Recording state.

## Capture Rules

- Show the real app UI, not marketing mockups.
- Do not include private tokens, customer recordings, unrelated desktop content, or unreleased BlitzReels account data.
- Keep subscription wording consistent with `AppStore/Metadata-macOS.md` and `AppStore/Metadata-iOS.md`.
- First screenshot should communicate the primary workflow; it appears most often in search and product-page previews.
