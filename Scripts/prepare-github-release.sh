#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN_DMG=1
RUN_WEBSITE=1
NOTARIZE_LOCAL=0

usage() {
  cat <<'USAGE'
Usage:
  Scripts/prepare-github-release.sh VERSION BUILD [options]

Options:
  --skip-dmg       Do not build the local macOS DMG.
  --skip-website   Do not run the website lint/build checks.
  --notarize       Notarize the local DMG. Requires Developer ID and notary credentials.
  -h, --help       Show this help.

Examples:
  Scripts/prepare-github-release.sh 0.1.1 2
  Scripts/prepare-github-release.sh 0.1.1 2 --notarize
USAGE
}

if [[ $# -lt 2 ]]; then
  usage >&2
  exit 2
fi

VERSION="$1"
BUILD="$2"
shift 2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-dmg)
      RUN_DMG=0
      ;;
    --skip-website)
      RUN_WEBSITE=0
      ;;
    --notarize)
      NOTARIZE_LOCAL=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

cd "$ROOT"

Scripts/set-version.py "$VERSION" "$BUILD"
Scripts/generate-xcode-project.sh

bash -n \
  Scripts/package-app.sh \
  Scripts/package-dmg.sh \
  Scripts/ci-macos-dmg.sh \
  Scripts/ci-ios-testflight.sh \
  Scripts/archive-app-store.sh \
  Scripts/prepare-github-release.sh \
  Scripts/bootstrap-github-repo.sh \
  Scripts/generate-sparkle-appcast.sh \
  Scripts/check-github-release-readiness.sh

python3 -m py_compile Scripts/set-version.py
python3 -m py_compile Scripts/sync-github-labels.py
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/macos-dmg.yml")' >/dev/null
python3 Scripts/generate-app-store-connect-fields.py --check

if [[ "$RUN_WEBSITE" == "1" ]]; then
  npm --prefix Web/blitzrecorder run lint
  npm --prefix Web/blitzrecorder run build
fi

if [[ "$RUN_DMG" == "1" ]]; then
  if [[ "$NOTARIZE_LOCAL" == "1" ]]; then
    NOTARIZE=1 ENTITLEMENTS_PATH="$ROOT/BlitzRecorder.local.entitlements" Scripts/ci-macos-dmg.sh
  else
    ALLOW_AD_HOC_RELEASE_SIGNING=1 ENTITLEMENTS_PATH="$ROOT/BlitzRecorder.local.entitlements" Scripts/ci-macos-dmg.sh
  fi

  DMG_PATH="$ROOT/build/Distributions/BlitzRecorder-${VERSION}-${BUILD}-macOS-universal.dmg"
  test -f "$DMG_PATH"
  (
    cd "$(dirname "$DMG_PATH")"
    shasum -a 256 "$(basename "$DMG_PATH")" > SHA256SUMS
  )
fi

cat <<EOF
Prepared BlitzRecorder $VERSION build $BUILD.

Next steps:
  git status --short
  git add README.md SECURITY.md CHANGELOG.md .github/PULL_REQUEST_TEMPLATE.md .github/ISSUE_TEMPLATE .github/release.yml .github/labels.json project.yml BlitzRecorder.xcodeproj/project.pbxproj .github/workflows/macos-dmg.yml .github/workflows/ios-testflight.yml .github/workflows/app-store-release.yml Scripts/set-version.py Scripts/sync-github-labels.py Scripts/prepare-github-release.sh Scripts/bootstrap-github-repo.sh Scripts/generate-sparkle-appcast.sh Scripts/check-github-release-readiness.sh Scripts/package-app.sh Scripts/package-dmg.sh Scripts/ci-macos-dmg.sh Scripts/ci-ios-testflight.sh Scripts/archive-app-store.sh Scripts/preflight-app-store-local.sh Scripts/validate-submission-artifacts.sh Scripts/app-store-connect-readiness.py Scripts/validate-launch-readiness.sh Scripts/prepare-app-store-review-package.sh Scripts/collect-release-evidence.sh
  git commit -m "Release BlitzRecorder $VERSION"
  git tag v$VERSION
  git push origin main --tags
EOF
