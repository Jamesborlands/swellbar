#!/bin/zsh
# Builds Swellbar.app into build/. Pass --install to copy it to /Applications and relaunch it.
set -euo pipefail
cd "${0:A:h}"

mkdir -p build
# Universal binary: Apple silicon and Intel.
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $arch-apple-macosx14.0 -sdk "$(xcrun --show-sdk-path)" \
    Sources/*.swift -o build/Swellbar-$arch
done
lipo -create build/Swellbar-arm64 build/Swellbar-x86_64 -output build/Swellbar

if [[ ! -f Resources/AppIcon.icns ]]; then
  iconset=build/AppIcon.iconset
  rm -rf $iconset && mkdir -p $iconset
  swiftc scripts/make_icon.swift -o build/make_icon && build/make_icon build/icon-1024.png
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon-1024.png --out $iconset/icon_${s}x${s}.png >/dev/null
    sips -z $((s*2)) $((s*2)) build/icon-1024.png --out $iconset/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns $iconset -o Resources/AppIcon.icns
fi

app=build/Swellbar.app
rm -rf $app
mkdir -p $app/Contents/MacOS $app/Contents/Resources
cp build/Swellbar $app/Contents/MacOS/Swellbar
cp Resources/Info.plist $app/Contents/Info.plist
cp Resources/AppIcon.icns $app/Contents/Resources/AppIcon.icns
codesign --force --sign - $app
echo "Built $app"

if [[ "${1:-}" == "--zip" ]]; then
  rm -f build/Swellbar.zip
  ditto -c -k --keepParent $app build/Swellbar.zip
  echo "Zipped build/Swellbar.zip"
fi

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Swellbar 2>/dev/null && sleep 1 || true
  rm -rf /Applications/Swellbar.app
  cp -R $app /Applications/Swellbar.app
  open /Applications/Swellbar.app
  echo "Installed to /Applications/Swellbar.app"
fi
