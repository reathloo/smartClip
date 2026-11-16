#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
  export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
swift build -c release
app="dist/SmartClip.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/SmartClip "$app/Contents/MacOS/SmartClip"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
resource_bundle=".build/release/SmartClip_SmartClip.bundle"
[[ -d "$resource_bundle" ]] || { echo "Missing localization bundle: $resource_bundle" >&2; exit 1; }
localization_root="$resource_bundle/Contents/Resources"
[[ -d "$localization_root" ]] || { echo "Missing localization resources: $localization_root" >&2; exit 1; }
for localization in "$localization_root"/*.lproj(N); do
  cp -R "$localization" "$app/Contents/Resources/"
done
zsh scripts/embed-sparkle.sh release "$app"
codesign --force --deep --sign - "$app"
echo "Built $app"
