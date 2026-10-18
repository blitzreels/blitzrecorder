#!/usr/bin/env bash
# Renders the app's SwiftUI surfaces offscreen (no app launch, no permission prompts) and builds one
# contact sheet that puts changed screens first, compared with the previous run.
#
#   Scripts/ui-proof.sh                 export + share + editor chrome (default)
#   Scripts/ui-proof.sh studio kit      several scopes
#   Scripts/ui-proof.sh all --open      everything, then open the sheet in the browser
#   Scripts/ui-proof.sh editor:audio,layout   only those editor tabs (also: notice, wide), a few seconds
#
# Scopes: export, share, editor, studio, kit, library, hud, silence, all.
set -euo pipefail

cd "$(dirname "$0")/.."

open_sheet=false
scopes=()
screens=""
for arg in "$@"; do
  case "$arg" in
    --open) open_sheet=true ;;
    editor:*) scopes+=(editor); screens="${arg#editor:}" ;;
    *) scopes+=("$arg") ;;
  esac
done
[[ ${#scopes[@]} -eq 0 ]] && scopes=(export share editor)

filters=()
for scope in "${scopes[@]}"; do
  case "$scope" in
    export) filters+=("EditorExportPresentationTests") ;;
    share) filters+=("HostedVideoAccountTests") ;;
    editor) filters+=("EditorChromeProofTests" "EditorPaneProofTests") ;;
    studio) filters+=("RecorderStudioProofTests" "AppShellProofTests") ;;
    kit) filters+=("UIKitProofTests") ;;
    library) filters+=("ProjectsProofTests" "HostedVideoTests") ;;
    hud) filters+=("RecordingHUDTests") ;;
    silence) filters+=("SilencePanePresentationTests") ;;
    all) filters+=("ProofTests" "EditorExportPresentationTests" "HostedVideoAccountTests" "HostedVideoTests"
                   "SilencePanePresentationTests" "RecordingHUDTests") ;;
    *) echo "Unknown scope: $scope" >&2; exit 64 ;;
  esac
done
filter=$(IFS='|'; echo "${filters[*]}")

root="build/ui-proof"
run="$root/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$run"
previous=""
[[ -L "$root/latest" ]] && previous="$(readlink "$root/latest")"

# The editor proof opens a real take. Cache one copy on the internal disk, then give each run a clone.
fixture="$root/take-fixture"
needs_take=false
[[ "$filter" == *EditorPaneProofTests* || " ${scopes[*]} " == *" all "* ]] && needs_take=true
if $needs_take && [[ ! -d "$fixture" ]]; then
  takes="${BLITZRECORDER_PROOF_TAKES:-/Volumes/harddrive/recordings/BlitzRecorder Source Takes}"
  latest="$(ls -dt "$takes"/*/ 2>/dev/null | head -1 || true)"
  if [[ -n "$latest" ]]; then
    echo "Caching proof take: $latest"
    mkdir -p "$fixture" && cp -R "$latest". "$fixture"/ && find "$fixture" -name '._*' -delete
  else
    echo "No take found in $takes; editor screens are skipped. Set BLITZRECORDER_PROOF_TAKES to a takes folder." >&2
  fi
fi
take_env=()
if $needs_take && [[ -d "$fixture" ]]; then
  clone="$run/.take"
  cp -cR "$fixture" "$clone" 2>/dev/null || cp -R "$fixture" "$clone"
  take_env=(BLITZRECORDER_EDITOR_PROOF_TAKE="$PWD/$clone")
fi

echo "Rendering: ${scopes[*]}"
log="$run/test.log"
if ! env "${take_env[@]}" BLITZRECORDER_PROOF_SCREENS="$screens" BLITZRECORDER_PROOF_HEIGHT="${BLITZRECORDER_PROOF_HEIGHT:-1400}" BLITZRECORDER_PROOF_SCALE="${BLITZRECORDER_PROOF_SCALE:-1}" BLITZRECORDER_EXPORT_UI_PROOF="$PWD/$run" BLITZRECORDER_SILENCE_UI_PROOF="$PWD/$run" \
    swift test --filter "$filter" >"$log" 2>&1; then
  grep -E "error:|failed" "$log" | head -20 >&2
  echo "Proof tests failed. Full log: $log" >&2
  exit 1
fi

rm -rf "$run/.take"
ln -sfn "$(basename "$run")" "$root/latest"
python3 -I Scripts/ui-proof-sheet.py "$run" ${previous:+"$root/$previous"}
ls -dt "$root"/2* 2>/dev/null | tail -n +6 | xargs rm -rf

if $open_sheet; then open "$run/index.html"; fi
