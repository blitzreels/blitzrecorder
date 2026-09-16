#!/bin/bash
# Render Resources/dmg/background.png from Scripts/dmg/render.py.
# Layout coordinates must stay in sync with Resources/dmg/dmgly.json.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
python3 "$here/render.py"
