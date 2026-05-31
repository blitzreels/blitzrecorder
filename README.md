# BlitzRecorder

Native Mac screen recording studio with an iPhone camera companion.

[Website](https://blitzrecorder.com)

BlitzRecorder helps creators record product demos, tutorials, walkthroughs, and short-form videos from one focused Mac workspace. It captures screen, camera, microphone, and system audio, with optional iPhone camera capture for higher-quality talking-head shots.

## Features

- Record a display, window, app, camera, microphone, and Mac system audio.
- Frame 16:9 and 9:16 videos before pressing record.
- Pair an iPhone as a remote camera with live preview and supported camera controls.
- Keep source files available so failed exports do not mean lost recordings.
- Open, reveal, rename, move, or retry a take after recording.

## Apps

| App | Platform | Purpose |
| --- | --- | --- |
| BlitzRecorder | macOS | Main recorder, layout canvas, source capture, export, and recovery workspace. |
| BlitzRecorder Camera | iOS | Companion camera that pairs with the Mac, records locally, and transfers the camera file back to the take. |

## Development

Requirements:

- macOS
- Xcode
- Swift Package Manager
- XcodeGen when regenerating the Xcode project
- Node.js for the website

Generate the Xcode project:

```bash
Scripts/generate-xcode-project.sh
```

Build and launch the Mac app:

```bash
./script/build_and_run.sh
```

Run Swift checks:

```bash
swift test
swift test --package-path Packages/BlitzRecorderCore
swift test --package-path Packages/BlitzRecorderTransport
```

Build the website:

```bash
cd Web/blitzrecorder
npm install
npm run build
```

## Repository

```txt
Apps/iOSCamera/              iPhone companion app
Packages/BlitzRecorderCore/  Shared recording and camera logic
Packages/BlitzRecorderTransport/  Pairing and transport layer
Sources/BlitzRecorderApp/    macOS app source
Tests/                       macOS app tests
Web/blitzrecorder/           Website
docs/                        Product, development, and release notes
```

## Status

BlitzRecorder is in active development. The public website is available at [blitzrecorder.com](https://blitzrecorder.com).
