# BlitzRecorder

A native Mac screen recorder with an iPhone camera companion.

[Website](https://blitzrecorder.com)

BlitzRecorder helps creators record product demos, tutorials, walkthroughs, and short videos from one Mac workspace. It captures screen, camera, microphone, and system audio. The free direct-download tier exports 1080p. The Early Lifetime License unlocks iPhone camera recording, 4K export, and 60 fps export.

## Features

- Record a display, window, app, camera, microphone, and Mac system audio.
- Frame 16:9 and 9:16 videos before pressing record.
- Pair an iPhone as a remote camera with live preview and supported camera controls with the Early Lifetime License.
- Keep source files when possible, so failed exports do not mean lost recordings.
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

Issues and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening larger changes.

Security reports should be sent by email. See [SECURITY.md](SECURITY.md).

Release notes are tracked in [CHANGELOG.md](CHANGELOG.md) and GitHub Releases.

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

BlitzRecorder is in active development. The public website is [blitzrecorder.com](https://blitzrecorder.com).

## License

BlitzRecorder uses a dual-license model:

- Open source under the GNU Affero General Public License v3.0 only. See [LICENSE](LICENSE).
- The direct-download Early Lifetime License unlocks paid app features in the official signed build.
- Commercial licenses are available for organizations that need non-AGPL terms. See [COMMERCIAL-LICENSE.md](COMMERCIAL-LICENSE.md).
