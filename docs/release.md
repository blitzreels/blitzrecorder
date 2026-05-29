# Release and CI

GitHub Actions validates pull requests and pushes, builds downloadable DMGs, and provides manual App Store/TestFlight lanes.

## Pull Request and Push CI

`.github/workflows/ci.yml` runs on pull requests and pushes to `main` or `codex/**`.

It runs:

- `swift test`
- shared package tests
- App Store Connect fixture and dry-run checks
- unsigned macOS Debug build
- unsigned iOS simulator Debug build

This lane does not require Apple credentials.

## macOS DMG

`.github/workflows/macos-dmg.yml` builds a downloadable DMG for pull requests, pushes, `v*` tags, and manual workflow runs.

The normal artifact lane does not need Apple credentials. It builds through `Scripts/ci-macos-dmg.sh`, packages the app through `Scripts/package-dmg.sh`, and uploads `build/Distributions/BlitzRecorder-*.dmg`.

Manual runs can set `notarize=1` when Developer ID and App Store Connect notary secrets are configured.

Run the same lane locally with:

```bash
ENTITLEMENTS_PATH="$PWD/BlitzRecorder.local.entitlements" Scripts/ci-macos-dmg.sh
```

## iOS TestFlight

`.github/workflows/ios-testflight.yml` is a manual lane for the free iPhone companion app. It installs signing credentials, runs local App Store checks, archives `BlitzRecorderCamera`, exports the iOS App Store package, and can upload to TestFlight with `upload=1`.

Run the same lane locally with:

```bash
TEAM_ID="$APPLE_TEAM_ID" \
ASC_KEY_ID="$ASC_KEY_ID" \
ASC_ISSUER_ID="$ASC_ISSUER_ID" \
ASC_PRIVATE_KEY="$ASC_PRIVATE_KEY" \
UPLOAD=0 \
Scripts/ci-ios-testflight.sh
```

Use `UPLOAD=1` only when TestFlight metadata, export compliance, privacy answers, and tester notes are ready.

## Combined App Store Release

`.github/workflows/app-store-release.yml` is a manual release lane for macOS, iOS, or both App Store targets.

Reusable local command:

```bash
TARGET=all EXPORT=1 UPLOAD=0 TEAM_ID="$APPLE_TEAM_ID" Scripts/archive-app-store.sh
```

Credential and secret setup is documented in [../AppStore/CI.md](../AppStore/CI.md).
