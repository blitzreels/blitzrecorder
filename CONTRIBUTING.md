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

Build the website:

```bash
cd Web/blitzrecorder
npm install
npm run build
```

## Security

Do not open a public issue for vulnerabilities, leaked credentials, private user data, or other sensitive reports.

Send sensitive reports to `support@blitzreels.com`.
