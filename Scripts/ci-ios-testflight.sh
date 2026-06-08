#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPLOAD="${UPLOAD:-0}"
SIMULATOR_BUILD="${SIMULATOR_BUILD:-1}"

cd "$ROOT"

if [[ "$SIMULATOR_BUILD" != "0" && "$SIMULATOR_BUILD" != "1" ]]; then
  echo "SIMULATOR_BUILD must be 0 or 1." >&2
  exit 2
fi

if [[ "$UPLOAD" != "0" && "$UPLOAD" != "1" ]]; then
  echo "UPLOAD must be 0 or 1." >&2
  exit 2
fi

if [[ "$SIMULATOR_BUILD" == "1" ]]; then
  xcodebuild \
    -project BlitzRecorder.xcodeproj \
    -scheme BlitzRecorderCamera \
    -configuration Debug \
    -sdk iphonesimulator \
    -derivedDataPath build/XcodeDerivedData-CI-iOS \
    CODE_SIGNING_ALLOWED=NO \
    build
fi

TARGET=ios \
EXPORT=1 \
UPLOAD="$UPLOAD" \
ALLOW_PROVISIONING_UPDATES="${ALLOW_PROVISIONING_UPDATES:-1}" \
Scripts/archive-app-store.sh
