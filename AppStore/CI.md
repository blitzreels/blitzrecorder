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

Set `UPLOAD=1` from the workflow dispatch UI only when the app records, subscription, screenshots, privacy labels, and reviewer notes are ready.
