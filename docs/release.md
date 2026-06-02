# Release and CI

GitHub Actions validates pull requests and pushes, builds downloadable DMGs, and provides manual App Store/TestFlight lanes.

## Pull request and push CI

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

The normal artifact lane can run without Apple credentials on non-tag builds. It builds through `Scripts/ci-macos-dmg.sh`, packages the app through `Scripts/package-dmg.sh`, and uploads `build/Distributions/BlitzRecorder-*.dmg`.

Release builds are triggered by Git tags that start with `v`, for example `v0.1.0`. Tagged builds create a universal macOS DMG, sign and notarize it, generate `SHA256SUMS`, and attach both files to the GitHub Release.

The DMG filename includes the app version, build number, platform, and architecture label:

```text
BlitzRecorder-0.1.0-1-macOS-universal.dmg
```

The app bundle inside the DMG is built as a universal binary by default:

```text
arm64 x86_64
```

Manual runs can set `notarize=1` when Developer ID and App Store Connect notary secrets are configured.

Run the same lane locally with:

```bash
ENTITLEMENTS_PATH="$PWD/BlitzRecorder.local.entitlements" Scripts/ci-macos-dmg.sh
```

For a local throwaway release build without Developer ID signing, use:

```bash
ALLOW_AD_HOC_RELEASE_SIGNING=1 ENTITLEMENTS_PATH="$PWD/BlitzRecorder.local.entitlements" Scripts/ci-macos-dmg.sh
```

To build only the native host architecture locally:

```bash
APP_ARCHS=native ALLOW_AD_HOC_RELEASE_SIGNING=1 ENTITLEMENTS_PATH="$PWD/BlitzRecorder.local.entitlements" Scripts/package-dmg.sh
```

## Versioning

`MARKETING_VERSION` is the public version, such as `0.1.0`. `CURRENT_PROJECT_VERSION` is the Apple build number, such as `1`.

Before preparing a release, run the readiness checker:

```bash
Scripts/check-github-release-readiness.sh
```

Before making the repository public, run:

```bash
Scripts/check-open-source-readiness.sh
```

If the GitHub repo is not created yet or your active `gh` account cannot access it, run the local checks only:

```bash
Scripts/check-github-release-readiness.sh --local-only
```

To create or connect the GitHub repository, use the dry-run bootstrap first:

```bash
Scripts/bootstrap-github-repo.sh --repo blitzreels/blitzrecorder
```

If the printed commands are correct, run:

```bash
Scripts/bootstrap-github-repo.sh --repo blitzreels/blitzrecorder --apply --push
```

Update both before a release:

```bash
Scripts/prepare-github-release.sh 0.1.1 2
```

That script updates the version/build references, regenerates the Xcode project, checks release metadata, runs the website checks, builds a local universal DMG, verifies both Mac architectures, and writes `build/Distributions/SHA256SUMS`.

For a faster version-only prep:

```bash
Scripts/prepare-github-release.sh 0.1.1 2 --skip-dmg --skip-website
```

Then commit the release prep and create a tag:

```bash
git tag v0.1.1
git push origin main --tags
```

The `v*` tag starts the macOS DMG workflow and publishes the GitHub Release assets.

## GitHub release secrets

Tagged macOS releases require Developer ID and App Store Connect notary secrets. You can configure them with:

```bash
DEVELOPER_ID_CERTIFICATE_PATH="$PWD/private/DeveloperID.p12" \
DEVELOPER_ID_CERTIFICATE_PASSWORD_FILE="$PWD/private/developer-id-password.txt" \
KEYCHAIN_PASSWORD="$(openssl rand -base64 32)" \
ASC_KEY_ID="$ASC_KEY_ID" \
ASC_ISSUER_ID="$ASC_ISSUER_ID" \
ASC_PRIVATE_KEY_PATH="$PWD/private/AuthKey_$ASC_KEY_ID.p8" \
Scripts/configure-github-release-secrets.sh
```

App Store and TestFlight workflows use Apple Distribution signing. Configure those separately:

```bash
APPLE_TEAM_ID="$APPLE_TEAM_ID" \
APPLE_DISTRIBUTION_CERTIFICATE_PATH="$PWD/private/AppleDistribution.p12" \
APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD_FILE="$PWD/private/apple-distribution-password.txt" \
KEYCHAIN_PASSWORD="$(openssl rand -base64 32)" \
ASC_KEY_ID="$ASC_KEY_ID" \
ASC_ISSUER_ID="$ASC_ISSUER_ID" \
ASC_PRIVATE_KEY_PATH="$PWD/private/AuthKey_$ASC_KEY_ID.p8" \
IOS_APP_STORE_PROVISION_PROFILE_PATH="$PWD/private/BlitzRecorderCamera.mobileprovision" \
Scripts/configure-github-app-store-secrets.sh
```

Use `--repo OWNER/REPO` if the current Git remote is not the GitHub repo you want to configure.

After configuring secrets, rerun:

```bash
Scripts/check-github-release-readiness.sh --repo OWNER/REPO
```

Sync repository labels for issue templates and generated release notes:

```bash
Scripts/sync-github-labels.py --repo OWNER/REPO
Scripts/sync-github-labels.py --repo OWNER/REPO --apply
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

## Combined App Store release

`.github/workflows/app-store-release.yml` is a manual release lane for macOS, iOS, or both App Store targets.

Reusable local command:

```bash
TARGET=all EXPORT=1 UPLOAD=0 TEAM_ID="$APPLE_TEAM_ID" Scripts/archive-app-store.sh
```

Credential and secret setup is documented in [../AppStore/CI.md](../AppStore/CI.md).
