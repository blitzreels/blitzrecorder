# iPhone Apple Log Capture Roadmap

## Customer Request

A customer asked whether BlitzRecorder's "full quality" iPhone camera recording means the iPhone's normal processed camera image, or a less-baked camera pipeline similar to Blackmagic Camera with Apple Log, Rec.709, LUT preview, and optional LUT burn-in.

Short answer for current product: not yet. BlitzRecorder currently records locally on the iPhone and transfers the file to the Mac, which is better than a compressed webcam or Continuity Camera style stream. It should not be positioned as Apple Log, Rec.709 camera-control capture, LUT preview, LUT burn-in, or RAW sensor capture.

## Goal

Add pro camera capture modes for the iPhone companion app so supported iPhones can record a less-baked camera image for editing and grading, while BlitzRecorder keeps its core workflow: control the iPhone from the Mac, record the source file on the iPhone, transfer the file into the take, and keep editing/exporting on the Mac.

## Non-Goals

- Do not claim RAW sensor capture for the first version.
- Do not build a full Blackmagic Camera replacement.
- Do not replace the existing HEVC local recording path for users who want simple recording.
- Do not require LUT burn-in for the first release.
- Do not block recording on iPhones that do not support Apple Log or ProRes.

## Market Reference

Blackmagic Camera positions its iOS app as adding digital film camera controls and image processing to iPhone/iPad, with manual controls for frame rate, shutter angle, white balance, and ISO, plus 10-bit Apple ProRes recording up to 4K where supported ([Blackmagic Camera tech specs](https://www.blackmagicdesign.com/products/blackmagiccamera/techspecs/W-DOC-04)).

This customer request is specifically about that class of workflow: less default iPhone Camera.app processing, more predictable color pipeline, and professional preview/output controls.

## Technical Basis

Apple exposes `AVCaptureColorSpace.appleLog`, described as BT.2020 primaries with an Apple-defined Log transfer curve, and `AVCaptureColorSpace.appleLog2`, described as Apple Gamut primaries with an Apple-defined Log curve ([AVCaptureColorSpace](https://developer.apple.com/documentation/avfoundation/avcapturecolorspace)).

Apple exposes `AVCaptureDevice.activeColorSpace` for setting the active capture color space. Apple notes that manual color-space selection requires disabling `AVCaptureSession.automaticallyConfiguresCaptureDeviceForWideColor`, and that changing the active color space while running disruptively reconfigures the capture pipeline and ends in-progress movie capture ([activeColorSpace](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activecolorspace)).

Apple's ProRes technote says ProRes capture requires manual AVCaptureSession configuration, a suitable 10-bit source format, and runtime validation of available codecs after the capture device is configured. It also describes two viable output paths: `AVCaptureMovieFileOutput` for simpler ProRes recording, or `AVCaptureVideoDataOutput` plus `AVAssetWriter` when the app needs access to video samples before writing ([TN3104: Recording video in Apple ProRes](https://developer.apple.com/documentation/technotes/tn3104-recording-video-in-apple-prores)).

Apple's `AVCaptureDevice.activeFormat` docs state that setting active format and frame durations should be done together during capture session configuration, and that active format and session preset are mutually exclusive on iOS ([activeFormat](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activeformat)).

## Product Requirements

### Capture Modes

Add an iPhone camera capture mode selector:

- Standard HEVC: current simple mode, default.
- Standard ProRes: available on supported iPhones and configurations.
- Apple Log ProRes: available only when lens, format, frame rate, codec, and color space support it.
- Rec.709 normalized output: later phase, likely export-time or live processed output rather than true capture color space.

The UI must clearly distinguish:

- Recording color space: what is written into the source camera file.
- Preview LUT: how the user sees the image while recording.
- Burn-in LUT: whether the LUT is applied to the recorded/exported output.

### Capability Discovery

The iPhone companion should report per-lens, per-format capability:

- Supported capture profiles: HEVC, ProRes, Apple Log ProRes.
- Supported color spaces: Standard/sRGB, P3/HLG where useful, Apple Log, Apple Log 2 when available.
- Supported frame rates for each profile.
- Whether a selected mode requires external storage, lower frame rate, or lower resolution.
- Storage headroom warnings for ProRes/Log.

### Mac Controls

The Mac remote camera controls should show only supported options for the selected iPhone/lens:

- Capture profile.
- Color mode.
- Resolution.
- Frame rate.
- LUT preview toggle.
- LUT selection.
- Optional burn-in toggle in later phases.

Unsupported choices should explain why they are unavailable, not silently disappear.

### Preview

For Apple Log, the user should not be forced to preview a flat Log image. Add LUT preview:

- Default Apple Log to Rec.709 preview LUT.
- Toggle preview LUT on/off.
- Keep recorded source as Log in the first phase.
- Apply preview LUT on the Mac monitor path if possible, so the iPhone can continue recording with `AVCaptureMovieFileOutput`.

### Output

First release should preserve the original Apple Log ProRes source file. Burn-in should be handled later, ideally during export.

Export-time options:

- Keep Log source untouched.
- Apply Apple Log to Rec.709 LUT to final export.
- Apply a user-selected LUT to final export.
- Persist LUT metadata in the take manifest.

Live burn-in is a later engineering milestone because it likely requires `AVCaptureVideoDataOutput` plus `AVAssetWriter`, sample-buffer color management, and real-time processing before writing.

## Implementation Roadmap

### Phase 0: Copy and Product Guardrails

- Replace ambiguous landing-page copy like "full quality" with "records locally on your iPhone at native camera quality instead of streaming a compressed webcam feed."
- Avoid "RAW sensor" language.
- Add future-facing copy only after Apple Log ships.

### Phase 1: Capability Model

- Add shared transport enums for `RemoteCameraColorMode` and/or extend capture profiles.
- Add color-space support to `RemoteCameraFormat`.
- Report whether each format supports Apple Log and Apple Log 2.
- Normalize settings so unsupported Log requests fall back safely to Standard HEVC or Standard ProRes.

Likely files:

- `Packages/BlitzRecorderCore/Sources/BlitzRecorderCore/RemoteCameraCapabilities.swift`
- `Packages/BlitzRecorderCore/Sources/BlitzRecorderCore/RemoteCameraMessages.swift`
- `Packages/BlitzRecorderCore/Sources/BlitzRecorderCore/RemoteCameraSettingsResolver.swift`
- `Apps/iOSCamera/Sources/CameraCaptureController.swift`

### Phase 2: Apple Log ProRes Recording

- Disable automatic wide-color configuration before manually setting color space.
- Select an active format that supports ProRes source requirements and the requested color space.
- Set `activeFormat`, `activeColorSpace`, and frame durations inside session configuration.
- Validate `movieOutput.availableVideoCodecTypes` after configuring the device.
- Prefer `AVCaptureMovieFileOutput` for v1 so the existing local-record-and-transfer flow remains intact.
- Add runtime telemetry/status labels for actual selected codec, format, frame rate, and color space.

Expected first implementation shape:

```swift
session.beginConfiguration()
session.automaticallyConfiguresCaptureDeviceForWideColor = false

try device.lockForConfiguration()
device.activeFormat = selectedFormat
device.activeColorSpace = .appleLog
device.activeVideoMinFrameDuration = frameDuration
device.activeVideoMaxFrameDuration = frameDuration
device.unlockForConfiguration()

session.commitConfiguration()

if movieOutput.availableVideoCodecTypes.contains(.proRes422) {
    movieOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.proRes422.rawValue], for: connection)
}
```

### Phase 3: LUT Preview

- Keep the recorded source as Apple Log.
- Apply a display transform only to preview frames.
- Prefer applying LUT on the Mac monitor preview path first, because BlitzRecorder already receives monitor frames separately from the iPhone recording file.
- Add a built-in Apple Log to Rec.709 preview LUT.
- Later, allow user LUT import.

Likely files:

- `Apps/iOSCamera/Sources/CameraCaptureController.swift`
- `Sources/BlitzRecorderApp/RemoteCameraMonitorSampleBufferFactory.swift`
- `Sources/BlitzRecorderApp/AppKitViews.swift`
- `Sources/BlitzRecorderApp/UI/RemoteCameraControlsPane.swift`

### Phase 4: Export-Time LUT Burn-In

- Add LUT selection to take settings or remote camera source settings.
- Persist LUT intent in the remote camera manifest.
- Apply LUT during final export/post-processing.
- Keep the original camera source untouched unless the user explicitly exports a baked output.

Likely files:

- `Sources/BlitzRecorderApp/OptimizedCompositionExporter.swift`
- `Sources/BlitzRecorderApp/LiveCompositorRenderer.swift`
- `Sources/BlitzRecorderApp/TakeFinalizer.swift`
- `Packages/BlitzRecorderCore/Sources/BlitzRecorderCore/RemoteCameraTransferManifest.swift`

### Phase 5: Optional Live LUT Burn-In

- Evaluate replacing or supplementing `AVCaptureMovieFileOutput` with `AVCaptureVideoDataOutput` plus `AVAssetWriter`.
- Use this only if customers need a baked Rec.709 or LUT-applied source file immediately after recording.
- Treat this as higher risk because it touches timing, audio/video sync, encoder settings, metadata, thermals, storage throughput, and dropped-frame behavior.

## UX Requirements

- Default remains simple: Standard HEVC.
- Pro users can switch to Apple Log from the Mac.
- The app should show "Apple Log source, Rec.709 preview" when a LUT preview is enabled.
- The record button should warn before starting if the chosen mode is likely to consume large storage.
- The app should surface actual mode after fallback, e.g. "Requested Apple Log ProRes, recording Standard HEVC because this iPhone/lens does not support Log at 4K60."

## Acceptance Criteria

- Supported iPhones expose Apple Log mode only for supported lens/format/frame-rate combinations.
- Starting a recording in Apple Log creates a valid `.mov` source file and transfers it to the Mac.
- The Mac UI shows actual codec, format, frame rate, and color mode for each recorded iPhone take.
- Standard HEVC behavior remains unchanged.
- If Apple Log is unsupported, the user sees a clear unavailable reason.
- LUT preview can be toggled without changing the recorded source file.
- Export-time LUT burn-in, once added, produces a normalized Rec.709 output while preserving the original Log source.

## Risks

- Device support differs by iPhone model, storage tier, lens, resolution, frame rate, codec, and OS version.
- Apple notes that changing active color space while running disruptively reconfigures capture and ends in-progress movie capture, so color mode changes must be blocked during recording ([activeColorSpace](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activecolorspace)).
- ProRes support must be validated after active format selection because available codecs are dynamic in the current capture configuration ([TN3104: Recording video in Apple ProRes](https://developer.apple.com/documentation/technotes/tn3104-recording-video-in-apple-prores)).
- LUT preview can diverge from final export if the same transform is not used consistently.
- Live burn-in can increase thermal load and dropped-frame risk.

## Open Questions

- Which minimum iPhone models should be supported for Apple Log in the product matrix?
- Should v1 expose only Apple Log ProRes, or also HLG/Rec.709 presets?
- Should LUT preview run on iPhone, Mac, or both?
- Which built-in LUT should ship first?
- Should user LUT import be supported in v1, or only a built-in Apple Log to Rec.709 transform?
- Should exported LUT burn-in be part of BlitzRecorder, BlitzReels handoff, or both?

## Source Links

- [AVCaptureColorSpace](https://developer.apple.com/documentation/avfoundation/avcapturecolorspace)
- [activeColorSpace](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activecolorspace)
- [activeFormat](https://developer.apple.com/documentation/avfoundation/avcapturedevice/activeformat)
- [automaticallyConfiguresCaptureDeviceForWideColor](https://developer.apple.com/documentation/avfoundation/avcapturesession/automaticallyconfigurescapturedeviceforwidecolor)
- [TN3104: Recording video in Apple ProRes](https://developer.apple.com/documentation/technotes/tn3104-recording-video-in-apple-prores)
- [Blackmagic Camera tech specs](https://www.blackmagicdesign.com/products/blackmagiccamera/techspecs/W-DOC-04)
