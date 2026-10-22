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

# A local dry run of the release build. Published releases take their version from the tag in CI.
export MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD"
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
Built BlitzRecorder $VERSION build $BUILD locally.

To publish it, tag and push. CI sets the version from the tag and the build number from its run number:
  git tag v$VERSION
  git push origin v$VERSION
EOF
