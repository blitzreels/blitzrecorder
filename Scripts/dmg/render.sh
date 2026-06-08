#!/bin/bash
# Render the BlitzRecorder DMG installer background from background.html into
# Resources/dmg/background.png (@1x, 660x400) and background@2x.png (1320x800)
# using headless Chrome. Re-run after editing background.html.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
src="file://$here/background.html"
out="$repo/Resources/dmg"
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

mkdir -p "$out"

render() { # scale  outfile
  "$chrome" --headless=new --disable-gpu --hide-scrollbars \
    --force-device-scale-factor="$1" --window-size=660,400 \
    --screenshot="$out/$2" "$src" >/dev/null 2>&1
}

render 1 background.png
render 2 background@2x.png
echo "wrote $out/background.png and background@2x.png"
