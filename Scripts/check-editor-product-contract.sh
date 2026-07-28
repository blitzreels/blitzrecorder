#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

failures=0

if ! rg -F 'ScenePreset.allCases.filter { $0.supports(captureLayout ?? .horizontal) }' \
    Sources/BlitzRecorderApp/UI/EditorView.swift >/dev/null; then
    echo "Editor scene presets must use the shared layout compatibility rule."
    failures=$((failures + 1))
fi

if ! rg -F 'ForEach(RecordingSettings.supportedFrameRates' \
    Sources/BlitzRecorderApp/UI/EditorView.swift >/dev/null; then
    echo "Editor FPS choices must use RecordingSettings.supportedFrameRates."
    failures=$((failures + 1))
fi

if rg -U 'writeRecordingProject\([\s\S]{0,200}settings: renderSettings' \
    Sources/BlitzRecorderApp/RecorderCoordinator.swift >/dev/null; then
    echo "Project export must not persist render settings as capture metadata."
    failures=$((failures + 1))
fi

if rg -F 'Recording at \(project.updatedAt' \
    Sources/BlitzRecorderApp/UI/ProjectLibraryView.swift >/dev/null; then
    echo "Recording identity must not derive from the last edit time."
    failures=$((failures + 1))
fi

if (( failures > 0 )); then
    exit 1
fi

echo "Editor product contract checks passed."
