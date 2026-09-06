# Contributing

Thanks for your interest in BlitzRecorder.

BlitzRecorder is open source, but it is also a focused product. Issues, ideas, and pull requests are welcome. That said, opening a PR does not mean it will be merged or added to the roadmap.

The maintainer keeps final say on what ships. This keeps the project coherent and avoids taking on work that cannot be maintained well.

## What to contribute

Good contributions are usually:

- Bug reports with clear reproduction steps.
- Small bug fixes.
- Documentation improvements.
- Focused usability improvements.
- Test coverage for existing behavior.

If you want to work on a larger change, open an issue first. It is better to check fit early than to spend time on a PR that cannot be merged.

## Pull requests

Please keep PRs small and focused. One behavior change per PR is easiest to review.

A PR may be declined or closed if it:

- Does not fit the product direction.
- Adds maintenance cost without enough benefit.
- Changes core UX, recording behavior, licensing, packaging, or distribution without prior discussion.
- Introduces private APIs, unclear third-party dependencies, or assets with uncertain rights.
- Includes secrets, credentials, customer data, private logs, or proprietary material.
- Is too large to review confidently.

Closing a PR is not a judgment on the contributor. It usually means the change does not fit the project right now.

## Licensing and contributor rights

BlitzRecorder is dual-licensed:

- Open source under the GNU Affero General Public License v3.0 only.
- Commercial licenses are available from the copyright holder under a separate written agreement.

By submitting a contribution, you agree that your contribution may be distributed under the project's open source license.

Because BlitzRecorder also has a commercial licensing model, larger code contributions may require a separate contributor agreement before they can be merged. If you are unsure whether this applies, ask before opening the PR.

Do not submit code, media, fonts, icons, or other assets unless you have the right to contribute them.

## Development

Generate the Xcode project:

```bash
Scripts/generate-xcode-project.sh
```

Run Swift checks:

```bash
swift test
swift test --package-path Packages/BlitzRecorderCore
swift test --package-path Packages/BlitzRecorderTransport
```

Run recording resilience checks on macOS:

```bash
Scripts/run-resilience.py quick
Scripts/run-resilience.py thread
Scripts/run-resilience.py address
Scripts/run-resilience.py disk
Scripts/run-resilience.py benchmark
Scripts/run-resilience.py soak --seconds 7200
```

The focused checks exercise capture failures, concurrent finalization, cancellation, damaged media, and project reloads.
The disk check fills an isolated 64 MB disk image and verifies that a failed save retains the recording sources.
Sanitizer failures, test failures, unexpected skips, and timeouts fail the command.

The endurance workload writes synthetic 640×360 video at 30 FPS with 48 kHz stereo audio in real time.
It decodes the saved video, checks timestamps and audio duration, and measures process memory after warmup.
Limits are 1% dropped frames, 100 ms audio/video drift, 64 MB steady memory growth, and 15% timing overhead.
Use 60 seconds for a local smoke run and 7200 seconds for a two-hour run.
These checks do not exercise camera hardware, ScreenCaptureKit permissions, physical device disconnection, or sleep/wake.
Validate those paths with the Dev app and a real recording before a release.

Benchmarks use fixed synthetic sources for 720p screen and 1080p screen-plus-camera exports.
They measure editor loading, unchanged canvas refresh, and export time after one warmup iteration.
They validate the exported frames and retain three measured iterations per fixture.
To enforce a 20% median regression limit, compare with a successful report from the same machine and toolchain:

```bash
Scripts/run-resilience.py benchmark --baseline /path/to/previous/report.json
```

Logs, JUnit XML, metrics, and machine/toolchain details are saved under `build/resilience/`.
Keep unrelated workloads closed when collecting a baseline.
The Recording Resilience workflow runs sanitizers and disk-full recovery for Swift pull requests and main-branch pushes.
Its manual action can run benchmarks or endurance checks for up to three hours; results are uploaded as artifacts.

Build the website:

```bash
cd Web/blitzrecorder
npm install
npm run build
```

## Security

Do not open a public issue for vulnerabilities, leaked credentials, private user data, or other sensitive reports.

Send sensitive reports to `support@blitzreels.com`.
