#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

python3 - <<'PY'
from pathlib import Path
import re
import sys

root = Path("Sources/BlitzRecorderApp/UI")
styles = {
    "BlitzButtonStyle": "BlitzButtonStyle.swift",
    "BlitzPressButtonStyle": "BlitzButtonStyle.swift",
    "BlitzSelectionButtonStyle": "InteractionStyle.swift",
    "BlitzMenuTriggerStyle": "BlitzMenuTriggerStyle.swift",
    "BlitzScenePresetButtonStyle": "BlitzUIPrimitives.swift",
    "BlitzToggleStyle": "BlitzToggleStyle.swift",
}
rules = [
    (r"\bPicker\s*\(|\.pickerStyle\s*\(|\.menuStyle\s*\(",
     "Use BlitzDropdown or BlitzSegmentedPicker for app-owned choices."),
    (r"\b(?:NewRecordingButtonStyle|EditRecordingButtonStyle|BlitzControlButtonStyle|BlitzSourcePickerRow|BlitzSourcePickerActionRow)\b",
     "Use the shared control primitive; feature-specific styles have been consolidated."),
    (r"\.blitz(?:Prominent)?GlassButton\s*\(",
     "Use blitzButton with an explicit emphasis."),
    (r"\.buttonStyle\(\.(?:bordered|borderedProminent|automatic)\)",
     "Use BlitzButtonStyle for app-owned buttons."),
]
typed_rules = [
    (r"\.system\(size:", "Use a BlitzType token (title, section, body, caption…) instead of a raw font size."),
    (r"\.font\(\.(?:largeTitle|title\d?|headline|subheadline|body|callout|footnote|caption2?)\)",
     "Use a BlitzType token instead of a system text style."),
    (r"(?:Color)?\.white\.opacity\(|Color\(red:", "Use BlitzUI color tokens instead of hard-coded colors."),
    (r"cornerRadius: (?:7|8|9|1[0-9])\b(?!\.)", "Use BlitzUI.controlRadius, cardRadius or surfaceRadius."),
    (r"Slider\([^)]*\bstep:", "Use BlitzInspectorSlider; stepped sliders draw tick marks."),
]
token_definition = re.compile(r"^\s*static (?:let|func)\b")
thin_weight = re.compile(r"weight: \.(?:ultraLight|thin|light)\b")
failures = []
for path in sorted(root.rglob("*.swift")):
    source = path.read_text()
    for line_number, line in enumerate(source.splitlines(), 1):
        for pattern, message in rules:
            if re.search(pattern, line):
                failures.append(f"{path}:{line_number}: {message}")
        if re.search(r"\.toggleStyle\(\.(?:switch|checkbox|automatic|button)\)", line) and path.name != "BlitzToggleStyle.swift":
            failures.append(f"{path}:{line_number}: Use BlitzToggleStyle for app-owned toggles.")
        defines_token = token_definition.match(line) or (
            path.name == "BlitzUIPrimitives.swift" and line.strip().startswith(".system(size: size")
        )
        if not defines_token:
            for pattern, message in typed_rules:
                if re.search(pattern, line):
                    failures.append(f"{path}:{line_number}: {message}")
        if thin_weight.search(line):
            failures.append(f"{path}:{line_number}: Thin symbol weights read as outline icons; use BlitzType.glyph.")
        if ".buttonStyle(.borderless)" in line and path.name != "NowPlayingMenuView.swift":
            failures.append(f"{path}:{line_number}: Borderless is reserved for the native status-menu transport.")
    for match in re.finditer(r"\b(?:struct|class)\s+(\w+)\s*:\s*(?:ButtonStyle|PrimitiveButtonStyle|ToggleStyle)\b", source):
        if styles.get(match.group(1)) != path.name:
            failures.append(f"{path}: Add a variant to the shared primitive instead of defining {match.group(1)}.")

if failures:
    print("\n".join(failures))
    sys.exit(1)
print("Design system checks passed.")
PY
