#!/bin/zsh
# Renders the README screenshots from live data. Launches through `open` on purpose: running
# build/Swellbar.app/Contents/MacOS/Swellbar straight from a terminal makes macOS file Swellbar's
# menu bar icon under the terminal app, and if that app is off in Settings > Menu Bar the icon
# disappears for good.
set -euo pipefail
cd "${0:A:h}/.."
docs=$PWD/docs

snap() {
  open -n build/Swellbar.app --args "$@"
  sleep 20
  pkill -f "$PWD/build/Swellbar.app" || true
}
snap --snapshot $docs/popover-delmar.png --snapshot-menubar $docs/menubar.png
snap --spot "Huntington Beach Pier" --snapshot $docs/popover-huntington.png --snapshot-picker $docs/spot-picker.png
snap --spot "Biarritz" --snapshot $docs/popover-biarritz.png
