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
    (r'(?:systemName|systemImage): "ellipsis', "No ⋯ menus. Show secondary actions with BlitzInlineActions and offer them on right-click."),
    (r'Text\((?:error|message)\)[^\n]*BlitzUI\.recordRed', "Errors use BlitzUI.warning; red is reserved for the record control."),
    (r'TextField\("0?0:00', "Use BlitzTimeStepper for times; don't make people type timecodes."),
]
typed_rules = [
    (r"\.system\(size:", "Use a BlitzType token (title, section, body, caption…) instead of a raw font size."),
    (r"\.font\(\.(?:largeTitle|title\d?|headline|subheadline|body|callout|footnote|caption2?)\)",
     "Use a BlitzType token instead of a system text style."),
    (r"(?:Color)?\.white\.opacity\(|Color\(red:", "Use BlitzUI color tokens instead of hard-coded colors."),
    (r"cornerRadius: (?:7|8|9|1[0-9])\b(?!\.)", "Use BlitzUI.controlRadius, cardRadius or surfaceRadius."),
    (r"Slider\([^)]*\bstep:", "Use BlitzInspectorSlider; stepped sliders draw tick marks."),
]
accent_literal = re.compile(r"0\.09, green: 1(?:\.0)?, blue: 0\.65")
status_glyphs = r"(?:play|pause|stop|backward\.end|forward\.end|exclamationmark\.triangle|exclamationmark\.circle|checkmark\.circle)\.fill"
rules += [
    (r'systemImage: "(?!' + status_glyphs + r'")[a-z0-9.]+\.fill"',
     "Action icons are outline. Fill marks selection (symbolVariant) or status (play, warning, success) only."),
    (r"(?:[sS]elected|isActive|isHovering)[^?\n]*\?\s*(?:BlitzType\.\w+|\.(?:semibold|bold|medium|regular))\s*:",
     "Keep one font per element in every state; selection changes fill and color, never weight."),
]
dock_files = {"RecordButton.swift", "BlitzSharedControls.swift", "EditRecordingButton.swift", "SavedRecordingChip.swift",
              "BottomDock.swift", "BlitzUIKit.swift", "BlitzUIKit+Components.swift", "BlitzUIKit+Feedback.swift"}
dock_emphasis = re.compile(r"blitzButton\(\.(?:dock|prominent)\)|emphasis: \.(?:dock|prominent)\b|BlitzButtonStyle\(\.(?:dock|prominent)\)")
token_definition = re.compile(r"^\s*static (?:let|func)\b")
action_symbol_literal = re.compile(r'"(?:scissors|square\.and\.arrow\.(?:up|down)|link|doc\.on\.doc|safari|'
                                   r'square\.and\.pencil|trash|folder|film\.stack)"')
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
        if dock_emphasis.search(line) and path.name not in dock_files:
            failures.append(f"{path}:{line_number}: Dock-size buttons belong to the dock; use accent, secondary or quiet on pages.")
        if thin_weight.search(line):
            failures.append(f"{path}:{line_number}: Thin symbol weights read as outline icons; use BlitzType.glyph.")
        if action_symbol_literal.search(line) and path.name != "BlitzUIPrimitives.swift":
            failures.append(f"{path}:{line_number}: Use the BlitzSymbols action constant (edit, export, share, copyLink, "
                            "openLink, rename, delete, folder, library, saveToMac) so every action keeps one icon.")
        if ".buttonStyle(.borderless)" in line and path.name != "NowPlayingMenuView.swift":
            failures.append(f"{path}:{line_number}: Borderless is reserved for the native status-menu transport.")
    for match in re.finditer(r"\b(?:struct|class)\s+(\w+)\s*:\s*(?:ButtonStyle|PrimitiveButtonStyle|ToggleStyle)\b", source):
        if styles.get(match.group(1)) != path.name:
            failures.append(f"{path}: Add a variant to the shared primitive instead of defining {match.group(1)}.")

for path in sorted(Path("Sources/BlitzRecorderApp").rglob("*.swift")):
    if path.name == "BlitzTheme.swift":
        continue
    for line_number, line in enumerate(path.read_text().splitlines(), 1):
        if accent_literal.search(line):
            failures.append(f"{path}:{line_number}: Use BlitzUI.accent or BlitzThemeStore; the accent follows the user's theme.")
        if "NSAppearance(named: .darkAqua)" in line and path.name not in {"BlitzTheme.swift", "RecordingHUD.swift"}:
            failures.append(f"{path}:{line_number}: Appearance follows Settings → Appearance (BlitzThemeStore.applyAppearance).")
    in_preview = False
    for line_number, line in enumerate(path.read_text().splitlines(), 1):
        if line.startswith("#Preview") or line.startswith("#if DEBUG"):
            in_preview = True
        if ".preferredColorScheme(.dark)" in line and not in_preview and path.name != "RecordingHUD.swift":
            failures.append(f"{path}:{line_number}: Don't pin dark; views must work in light and dark.")

if failures:
    print("\n".join(failures))
    sys.exit(1)
print("Design system checks passed.")
PY
