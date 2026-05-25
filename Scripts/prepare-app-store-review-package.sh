#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="0.1.0"
BUILD="1"
PACKAGE_ROOT="${PACKAGE_ROOT:-build/AppStoreReviewPackage}"
PACKAGE_DIR="$PACKAGE_ROOT/BlitzRecorder-$VERSION-build-$BUILD"
RUN_VALIDATION=1

usage() {
  cat <<'USAGE'
Usage:
  Scripts/prepare-app-store-review-package.sh [--skip-validation]

Creates a local App Store review handoff folder under build/AppStoreReviewPackage
with metadata, screenshots, legal source pages, setup worksheets, and release
evidence. This does not create App Store Connect records or signed archives.

Environment overrides:
  PACKAGE_ROOT=build/AppStoreReviewPackage
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-validation)
      RUN_VALIDATION=0
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_file() {
  [[ -f "$1" ]] || {
    echo "error: missing file: $1" >&2
    exit 1
  }
}

copy_file() {
  local source="$1"
  local destination="$2"
  require_file "$source"
  mkdir -p "$(dirname "$PACKAGE_DIR/$destination")"
  cp "$source" "$PACKAGE_DIR/$destination"
}

image_dimensions() {
  local file="$1"
  sips -g pixelWidth -g pixelHeight "$file" 2>/dev/null |
    awk '
      /pixelWidth/ { width = $2 }
      /pixelHeight/ { height = $2 }
      END {
        if (width && height) {
          print width "x" height
        }
      }
    '
}

sha256() {
  shasum -a 256 "$1" | awk '{ print $1 }'
}

manifest_line_for_file() {
  local file="$1"
  local relative="${file#$PACKAGE_DIR/}"
  local checksum
  checksum="$(sha256 "$file")"

  case "$file" in
    *.png|*.jpg|*.jpeg)
      local dimensions
      dimensions="$(image_dimensions "$file")"
      printf -- '- `%s` (%s, sha256 `%s`)\n' "$relative" "${dimensions:-unknown dimensions}" "$checksum"
      ;;
    *)
      printf -- '- `%s` (sha256 `%s`)\n' "$relative" "$checksum"
      ;;
  esac
}

write_manifest() {
  cat >"$PACKAGE_DIR/Manifest.md" <<EOF
# BlitzRecorder App Store Review Package

Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

## Release Identity

- Version: \`$VERSION\`
- Build: \`$BUILD\`
- macOS bundle ID: \`dev.blitzreels.blitzrecorder\`
- iOS companion bundle ID: \`dev.blitzreels.blitzrecorder.camera\`
- Subscription product ID: \`dev.blitzreels.blitzrecorder.pro.monthly\`
- Subscription price: \`\$4.99 per month\`
- Free quota: \`3 free exports\`

## Contents

EOF

  while IFS= read -r file; do
    manifest_line_for_file "$file" >>"$PACKAGE_DIR/Manifest.md"
  done < <(find "$PACKAGE_DIR" -type f ! -name Manifest.md | sort)

  cat >>"$PACKAGE_DIR/Manifest.md" <<'EOF'

## Still Required Outside This Package

- Create App Store Connect app records.
- Create and price the auto-renewable subscription.
- Upload signed App Store archives.
- Run live App Store Connect verification with API credentials.
- Verify a positive production BlitzReels entitlement token.
- Complete physical Mac/iPhone/iPad QA.
- Complete legal/privacy review.
EOF
}

python3 Scripts/generate-app-store-connect-fields.py >/dev/null
python3 Scripts/generate-app-store-questionnaire-answers.py >/dev/null
python3 Scripts/generate-app-store-privacy-labels.py >/dev/null

if [[ "$RUN_VALIDATION" == "1" ]]; then
  Scripts/validate-launch-readiness.sh
  Scripts/validate-submission-artifacts.sh
fi

rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"

copy_file "AppStore/Metadata.md" "Metadata/Metadata.md"
copy_file "AppStore/AppStoreConnectFields.generated.json" "Metadata/AppStoreConnectFields.generated.json"
copy_file "AppStore/Metadata-macOS.md" "Metadata/Metadata-macOS.md"
copy_file "AppStore/Metadata-iOS.md" "Metadata/Metadata-iOS.md"
copy_file "AppStore/ReviewNotes.md" "Metadata/ReviewNotes.md"
copy_file "AppStore/PrivacyNutritionLabels.md" "Metadata/PrivacyNutritionLabels.md"
copy_file "AppStore/PrivacyNutritionLabels.generated.json" "Metadata/PrivacyNutritionLabels.generated.json"
copy_file "AppStore/AppStoreQuestionnaires.md" "Metadata/AppStoreQuestionnaires.md"
copy_file "AppStore/AppStoreQuestionnaireAnswers.generated.json" "Metadata/AppStoreQuestionnaireAnswers.generated.json"
copy_file "AppStore/AppStoreConnectManualSetup.md" "Metadata/AppStoreConnectManualSetup.md"

copy_file "AppStore/ReleaseEvidence.md" "Evidence/ReleaseEvidence.md"
copy_file "AppStore/ReleaseEvidence.generated.md" "Evidence/ReleaseEvidence.generated.md"
copy_file "AppStore/DeviceQAChecklist.md" "Evidence/DeviceQAChecklist.md"
copy_file "AppStore/Screenshots.md" "Evidence/Screenshots.md"
copy_file "AppStore/BlitzReelsEntitlementContract.md" "Evidence/BlitzReelsEntitlementContract.md"

copy_file "Web/blitzrecorder/index.html" "PublicWebSource/index.html"
copy_file "Web/blitzrecorder/privacy.html" "PublicWebSource/privacy.html"
copy_file "Web/blitzrecorder/terms.html" "PublicWebSource/terms.html"
copy_file "Web/blitzrecorder/support.html" "PublicWebSource/support.html"
copy_file "Web/blitzrecorder/styles.css" "PublicWebSource/styles.css"

while IFS= read -r screenshot; do
  relative="${screenshot#AppStore/ScreenshotAssets/}"
  copy_file "$screenshot" "Screenshots/$relative"
done < <(find AppStore/ScreenshotAssets -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) | sort)

write_manifest
python3 Scripts/update-release-evidence.py >/dev/null
copy_file "AppStore/ReleaseEvidence.md" "Evidence/ReleaseEvidence.md"
write_manifest

echo "App Store review package prepared at $PACKAGE_DIR"
