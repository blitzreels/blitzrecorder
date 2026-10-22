#!/usr/bin/env bash
# Versions live in one place: project.yml. A tagged release build overrides the Mac app's version with
# MARKETING_VERSION and CURRENT_PROJECT_VERSION, which CI takes from the tag and the run number.
# Source this file; ROOT must point at the repository root.

project_setting() {
  local target="$1" key="$2"
  awk -v target="$target" -v key="$key:" '
    /^targets:/ { in_targets = 1; next }
    in_targets && /^[^ ]/ { in_targets = 0 }
    in_targets && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { current = $1; sub(":", "", current) }
    in_targets && current == target && $1 == key { gsub(/"/, "", $2); print $2; exit }
  ' "$ROOT/project.yml"
}

mac_marketing_version() { echo "${MARKETING_VERSION:-$(project_setting BlitzRecorder MARKETING_VERSION)}"; }
mac_build_number() { echo "${CURRENT_PROJECT_VERSION:-$(project_setting BlitzRecorder CURRENT_PROJECT_VERSION)}"; }
ios_marketing_version() { project_setting BlitzRecorderCamera MARKETING_VERSION; }
ios_build_number() { project_setting BlitzRecorderCamera CURRENT_PROJECT_VERSION; }
