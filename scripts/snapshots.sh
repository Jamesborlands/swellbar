#!/bin/zsh
# Renders the README screenshots from live data, dark and light (-light.png). The popover and
# spot picker are captured from their real windows, so they show the system's Liquid Glass over
# whatever is behind them on screen. Launches through `open` on purpose: running
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
  sleep 2
}
for look in dark light; do
  sfx=${${look:#dark}:+-$look}
  snap --appearance $look --snapshot $docs/popover-delmar$sfx.png
  snap --appearance $look --spot "Huntington Beach Pier" --snapshot $docs/popover-huntington$sfx.png --snapshot-picker $docs/spot-picker$sfx.png
  snap --appearance $look --spot "Biarritz" --snapshot $docs/popover-biarritz$sfx.png
done
snap --snapshot-menubar $docs/menubar.png
