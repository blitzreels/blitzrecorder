# BlitzRecorder CI Setup

## Pull Request CI

`.github/workflows/ci.yml` runs unsigned checks on GitHub-hosted macOS runners:

- `swift test`
- shared package tests
- App Store Connect fixture and dry-run checks
- unsigned macOS Debug build
- unsigned iOS simulator Debug build

This lane does not need Apple credentials.

## App Store Release CI

`.github/workflows/app-store-release.yml` is a manual `workflow_dispatch` release lane. Store these as GitHub Actions secrets, ideally scoped to an `app-store` environment with required approval:

| Secret | Purpose |
| --- | --- |
| `APPLE_TEAM_ID` | Apple Developer Team ID, for example `54LJ85K2P7`. |
| `ASC_KEY_ID` | App Store Connect API key ID. |
| `ASC_ISSUER_ID` | App Store Connect issuer ID. |
| `ASC_PRIVATE_KEY` | Full `.p8` private key contents. |
| `APPLE_DISTRIBUTION_CERTIFICATE_BASE64` | Base64-encoded Apple Distribution `.p12`. |
| `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD` | Password for the `.p12`. |
| `KEYCHAIN_PASSWORD` | Temporary CI keychain password. |
| `MAC_APP_STORE_PROVISION_PROFILE_BASE64` | Optional base64 macOS App Store `.provisionprofile`. |
| `IOS_APP_STORE_PROVISION_PROFILE_BASE64` | Optional base64 iOS App Store `.mobileprovision`. |

Encode local signing files with:

```bash
base64 -i AppleDistribution.p12 | pbcopy
base64 -i BlitzRecorder.provisionprofile | pbcopy
base64 -i BlitzRecorderCamera.mobileprovision | pbcopy
```

The release workflow installs the certificate and any provided profiles, runs local App Store checks, then calls:

```bash
TEAM_ID="$APPLE_TEAM_ID" \
ASC_KEY_ID="$ASC_KEY_ID" \
ASC_ISSUER_ID="$ASC_ISSUER_ID" \
ASC_PRIVATE_KEY="$ASC_PRIVATE_KEY" \
TARGET=all \
EXPORT=1 \
UPLOAD=0 \
ALLOW_PROVISIONING_UPDATES=1 \
Scripts/archive-app-store.sh
```

Set `UPLOAD=1` from the workflow dispatch UI only when app records, free-access QA, screenshots, privacy labels, and reviewer notes are ready.

## macOS DMG CI

`.github/workflows/macos-dmg.yml` builds a downloadable DMG for quick testing on every pull request, every push to `main` or `codex/**`, every `v*` tag, and manual `workflow_dispatch` runs.

The normal artifact lane can run without Apple credentials on non-tag builds. It calls `Scripts/ci-macos-dmg.sh`, packages the app through `Scripts/package-dmg.sh`, and uploads `build/Distributions/BlitzRecorder-*.dmg` plus `SHA256SUMS` as the `blitzrecorder-macos-dmg` workflow artifact. When the workflow runs for a `v*` tag, it signs and notarizes the universal DMG, generates a signed Sparkle `appcast.xml`, then attaches the DMG, checksum file, and appcast to the matching GitHub Release.

For a signed and notarized manual DMG, configure these additional GitHub Actions secrets, then run the workflow manually with `notarize=1`:

| Secret | Purpose |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Base64-encoded Developer ID Application `.p12`. |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password for the Developer ID `.p12`. |
| `KEYCHAIN_PASSWORD` | Temporary CI keychain password. |
| `ASC_KEY_ID` | App Store Connect API key ID for notarization. |
| `ASC_ISSUER_ID` | App Store Connect issuer ID. |
| `ASC_PRIVATE_KEY` | Full `.p8` private key contents. |
| `SPARKLE_PUBLIC_ED_KEY` | Public Sparkle EdDSA key embedded in direct DMG builds. |
| `SPARKLE_PRIVATE_ED_KEY` | Private Sparkle EdDSA key used to sign `appcast.xml`. |

Configure release, Sparkle, App Store, and TestFlight secrets through the GitHub Actions secrets UI or `gh secret set`. Do not commit certificates, provisioning profiles, private keys, or local secret helper scripts.

Check the repo, workflow, local scripts, and required secrets with:

```bash
Scripts/check-github-release-readiness.sh
```

If the GitHub repo has not been created or the `origin` remote points to a repo the active `gh` account cannot access, run the bootstrap dry-run:

```bash
Scripts/bootstrap-github-repo.sh --repo blitzreels/blitzrecorder
```

Then apply it after confirming the printed commands:

```bash
Scripts/bootstrap-github-repo.sh --repo blitzreels/blitzrecorder --apply --push
```

## Public Source Release

Before publishing source, run the public-tree gate:

```bash
Scripts/check-open-source-readiness.sh
```

If the repository has private development history, publish from a fresh-history tree instead of making old refs public.

The DMG lane stages the app with `ditto`, signs the DMG when a Developer ID Application identity is available, verifies the image, verifies the DMG signature when present, mounts it, checks `LSMinimumSystemVersion`, checks Mach-O minimum macOS metadata, and verifies the app code signature. Manual `notarize=1` also runs `spctl -a -t open`, staples the DMG, and validates the staple.

Release DMGs are universal by default and must contain both `arm64` and `x86_64` slices. The expected filename shape is:

```text
BlitzRecorder-0.1.0-1-macOS-universal.dmg
```

Run the same lane locally with:

```bash
ENTITLEMENTS_PATH="$PWD/BlitzRecorder.local.entitlements" Scripts/ci-macos-dmg.sh
```

Use `NOTARIZE=1` only on a machine or CI runner with Developer ID and notary credentials configured.

## iOS TestFlight CI

`.github/workflows/ios-testflight.yml` is a manual `workflow_dispatch` lane for the free iPhone companion app. It installs the Apple Distribution certificate and optional iOS provisioning profile, runs App Store Connect local checks, runs an unsigned iOS simulator build, archives `BlitzRecorderCamera`, exports the iOS App Store package, and optionally uploads to App Store Connect/TestFlight.

It uses the same App Store signing secrets as the general release lane:

| Secret | Purpose |
| --- | --- |
| `APPLE_TEAM_ID` | Apple Developer Team ID. |
| `ASC_KEY_ID` | App Store Connect API key ID. |
| `ASC_ISSUER_ID` | App Store Connect issuer ID. |
| `ASC_PRIVATE_KEY` | Full `.p8` private key contents. |
| `APPLE_DISTRIBUTION_CERTIFICATE_BASE64` | Base64-encoded Apple Distribution `.p12`. |
| `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD` | Password for the `.p12`. |
| `KEYCHAIN_PASSWORD` | Temporary CI keychain password. |
| `IOS_APP_STORE_PROVISION_PROFILE_BASE64` | Optional base64 iOS App Store `.mobileprovision`. |

Manual dispatch input:

| Input | Purpose |
| --- | --- |
| `upload=0` | Archive and export only. Use this for verification. |
| `upload=1` | Export with App Store Connect upload destination so the build appears in TestFlight. |

Run the same lane locally with:

```bash
TEAM_ID="$APPLE_TEAM_ID" \
ASC_KEY_ID="$ASC_KEY_ID" \
ASC_ISSUER_ID="$ASC_ISSUER_ID" \
ASC_PRIVATE_KEY="$ASC_PRIVATE_KEY" \
UPLOAD=0 \
Scripts/ci-ios-testflight.sh
```

Use `UPLOAD=1` only when the TestFlight metadata, export compliance, privacy answers, and tester notes are ready.
