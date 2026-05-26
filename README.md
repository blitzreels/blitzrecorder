# BlitzRecorder

Native macOS screencast recorder focused on low-overhead separate HEVC streams:

- screen and camera recorded as separate `.mov`, `.mp4`, or `.m4v` files
- Shorts 9:16 or YouTube 16:9 output canvas with full-aspect screen capture
- microphone audio recorded as a separate `.m4a`
- source rows for Screen Capture, Camera, System Audio, and Microphone
- macOS screen picker flow via `SCContentSharingPicker` to avoid the broad Screen Recording permission path when possible
- display, camera, and microphone device pickers
- rule-of-thirds framing overlay plus microphone/system-audio volume controls
- Capture and Export settings tabs, with output folder, quality, and format grouped under Export
- selectable HEVC video container output through AVFoundation/VideoToolbox
- framerate controls
- pause/resume with timestamp retiming so pauses are removed from the file
- rule-of-thirds overlay window
- red flashing menu bar indicator while paused
- quick merge of the last take into a picture-in-picture HEVC export
- smooth screen zoom menu actions
- automatic transcription after stop, followed by file/folder renaming
- optional local small-LLM title generation through Ollama (`qwen2.5:0.5b`, `llama3.2:1b`, or `gemma3:1b`) with a fallback slugger

## Product & Pricing Model

BlitzRecorder is a separate app from BlitzReels. Treat it as the paid recording product in the BlitzReels family:

- **BlitzRecorder for macOS**: standalone recording app and the only app that sells Pro access.
- **BlitzRecorder Camera for iPhone**: free companion camera app, with no paywall and no in-app purchases.
- **BlitzReels**: separate product; eligible active BlitzReels subscribers can unlock BlitzRecorder Pro as an included benefit.

Recommended pricing:

- Free: 3 finished exports.
- Pro monthly: `$7.99/month`.
- Pro annual: `$49.99/year`.
- BlitzReels bundle: included for eligible active BlitzReels subscribers.

The iPhone app should stay free because it is a companion input device for the Mac recorder, not a standalone paid camera product. Keeping purchase and restore flows only in the Mac app avoids confusing App Store users and avoids bad reviews from people who install the iPhone app expecting it to work without BlitzRecorder for Mac.

Licenses are bound to the App Store channel for launch. Do not add LemonSqueezy, Paddle, Stripe license keys, custom device activation limits, or a separate BlitzRecorder account system to the App Store build. A direct-download Mac app could add that later as a separate distribution channel, but it is intentionally out of scope for the App Store version.

## Auth & Entitlement Model

Do not require a BlitzRecorder account for normal App Store customers. The Mac app should support two Pro entitlement paths:

1. **App Store subscription**: the Mac app sells, restores, and verifies BlitzRecorder Pro monthly and annual subscriptions through StoreKit. StoreKit entitlement state unlocks unlimited Mac exports. The iPhone companion does not sell or restore the subscription.
2. **BlitzReels included access**: the Mac app opens BlitzReels sign-in only when the user wants to unlock included access from an existing BlitzReels subscription. BlitzReels redirects back to `blitzrecorder://auth/blitzreels?token=<access-token>`. The Mac app stores that token in the macOS Keychain and calls the BlitzReels entitlement endpoint. A response of `{ "active": true, "planName": "..." }` unlocks Pro.

The iPhone companion should not need its own auth. It pairs locally with the Mac app, records the high-quality camera master locally on the iPhone, transfers it back to the Mac, and lets the Mac enforce export entitlement. If the Mac is free, the user can still test the full workflow within the free export allowance. If the Mac is Pro through StoreKit or BlitzReels, exports remain unlimited.

## Build

```bash
cd ~/dev/blitzreels/blitzrecorder
./script/build_and_run.sh
```

The run script builds, signs, installs `/Applications/BlitzRecorder.app`, and launches that stable app identity. Use it instead of launching random build-path copies, because macOS TCC keys screen-recording approval to bundle identity, code signature, and app location.

Useful debug commands:

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --reset-screen-permission
```

## Workspace Layout

The repo is set up as a small native Apple monorepo:

- `Sources/BlitzRecorderApp`: macOS recorder app.
- `Apps/iOSCamera`: iPhone companion app for camera mirroring and remote camera controls.
- `Packages/BlitzRecorderCore`: shared remote-camera protocol models.
- `Packages/BlitzRecorderTransport`: shared Bonjour discovery/advertising and JSON message encoding/decoding utilities.
- `project.yml`: XcodeGen spec for one Xcode project with macOS and iOS targets.

Generate the Xcode project:

```bash
Scripts/generate-xcode-project.sh
```

Build checks:

```bash
swift test
swift test --package-path Packages/BlitzRecorderCore
swift test --package-path Packages/BlitzRecorderTransport
xcodebuild -project BlitzRecorder.xcodeproj -scheme BlitzRecorder -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project BlitzRecorder.xcodeproj -scheme BlitzRecorderCamera -configuration Debug -sdk iphonesimulator -derivedDataPath build/XcodeDerivedData-PackageCheck CODE_SIGNING_ALLOWED=NO build
```

The iOS target depends on the shared `BlitzRecorderCore` and `BlitzRecorderTransport` package products. Build the iOS scheme through Xcode so package modules and the app share one derived data workspace.

## macOS Screen Recording Context

Screen Recording is deliberately harder than Camera/Microphone on macOS. Camera and mic can be authorized with normal prompts. Broad screen capture cannot reliably be granted from an app prompt; local logs showed:

```text
Service kTCCServiceScreenCapture does not allow prompting; returning denied.
```

For programmatic ScreenCaptureKit capture through `SCShareableContent`, macOS requires the app to be manually enabled in System Settings under **Privacy & Security -> Screen & System Audio Recording**, then fully quit and reopened. Renaming the app, changing the bundle id, switching between debug/installed copies, or rebuilding with a different signature can make TCC treat it as a different app.

BlitzRecorder therefore supports two screen paths:

- **Pick Screen...**: uses Apple's `SCContentSharingPicker`; the user explicitly picks a screen, window, or app, and macOS grants that selected capture session without broad Screen Recording approval.
- **Display picker**: uses programmatic `SCShareableContent`; this still needs broad Screen & System Audio Recording permission.

System audio still uses the broad Screen & System Audio Recording permission path.

Sources:

- Apple WWDC23 Privacy: `SCContentSharingPicker` handles permission for explicitly selected content.
- Nonstrict ScreenCaptureKit notes: programmatic `SCShareableContent` requires Screen Recording authorization, picker flow does not.
- Local BlitzRecorder TCC logs: `kTCCServiceScreenCapture` returned denied because the service does not allow app prompting.

The first recording still requires macOS camera, microphone, and speech recognition permissions for those sources.

Each take writes source files to a temporary per-recording scratch folder first, then exports the final video directly into the selected recording folder. The scratch folder is removed after a successful export. Video file extensions match the selected output format:

- `slug-screen.mov`, `slug-screen.mp4`, or `slug-screen.m4v`
- `slug-camera.mov`, `slug-camera.mp4`, or `slug-camera.m4v`
- `slug-audio.m4a`
- `slug-system-audio.m4a`
- `slug-transcript.txt`
- final output in the recording folder: `slug-final.mov`, `slug-final.mp4`, or `slug-final.m4v`

## Stack & forward-looking notes

BlitzRecorder is built on the most modern Apple stack available in 2026, intentionally:

- **SwiftUI** for all new UI (sidebars, dock, top bar, inspector). Targets macOS 26 (Tahoe) so Liquid Glass APIs (`.glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)` / `.glassProminent`) are first-class. SF Symbols 6, `@Observable` view models, `NavigationSplitView`/`Inspector`.
- **AppKit** kept for what SwiftUI can't yet do cleanly: `NSWindow` + `NSStatusItem`, the preview stage (drag-resize, `CALayer` masks, `AVCaptureVideoPreviewLayer` hosting, custom `NSBezierPath` drawing). Wrapped into SwiftUI via `NSViewRepresentable` (`Bridges.swift`) and `NSHostingView` (`MainWindowController`).
- **No Catalyst, no Tauri, no Electron** — direct access to ScreenCaptureKit / AVFoundation / SCContentSharingPicker / VideoToolbox is the whole point of this app, and Apple's TCC is brittle enough already without adding a wrapper layer.

### Apple AI integrations worth migrating to later

- **Foundation Models framework** (macOS 26): on-device LLM. Should replace the current `TitleGenerator` Ollama dependency — drops the external install, runs locally on Apple Silicon, more private, faster.
- **`SpeechTranscriber` v2** (macOS 26): replaces the older `SFSpeechRecognizer` we use today. Faster, more accurate, multilingual.
- **Writing Tools / Translation / Image Playground**: available in any SwiftUI app on macOS 26.
- **MLX**: if we want to train/run custom models locally on Apple Silicon.

The combo `SwiftUI + Foundation Models + SpeechTranscriber v2` is the most modern Apple-native AI stack in 2026 — fully local, fully private, free.
