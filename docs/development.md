# Development

## Requirements

- macOS with the current Xcode toolchain used by the project
- Swift Package Manager
- XcodeGen when regenerating `BlitzRecorder.xcodeproj`
- Optional: Ollama for local title generation experiments

## Generate the Xcode project

```bash
Scripts/generate-xcode-project.sh
```

The generated project contains the macOS recorder target, the iOS companion target, and the shared Swift packages.

## Build and run the Mac app

```bash
ENTITLEMENTS_PATH="$PWD/BlitzRecorder.local.entitlements" Scripts/package-app.sh
rm -rf /Applications/BlitzRecorder.app
ditto build/BlitzRecorder.app /Applications/BlitzRecorder.app
open /Applications/BlitzRecorder.app
```

This builds, signs, installs, and launches a stable `/Applications/BlitzRecorder.app` identity. Use that for local testing instead of launching arbitrary build products because macOS privacy grants are tied to bundle identity, code signature, and app location.

Before rebuilding or restarting the Mac app during debugging, check which copy is currently running:

```bash
pgrep -x BlitzRecorder && ps -axo pid,lstart,comm,args | rg 'BlitzRecorder'
```

## Test and build checks

```bash
swift test
swift test --package-path Packages/BlitzRecorderCore
swift test --package-path Packages/BlitzRecorderTransport
xcodebuild -project BlitzRecorder.xcodeproj -scheme BlitzRecorder -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project BlitzRecorder.xcodeproj -scheme BlitzRecorderCamera -configuration Debug -sdk iphonesimulator -derivedDataPath build/XcodeDerivedData-PackageCheck CODE_SIGNING_ALLOWED=NO build
```

The iOS target depends on `BlitzRecorderCore` and `BlitzRecorderTransport`. Build the iOS scheme through Xcode or `xcodebuild` so package modules and the app share one derived data workspace.

## Local packaging checks

```bash
ENTITLEMENTS_PATH="$PWD/BlitzRecorder.local.entitlements" Scripts/ci-macos-dmg.sh
```

Use the local entitlements file for debug and ad-hoc DMG validation. Keep release and App Store entitlement files aligned with their distribution channel.
