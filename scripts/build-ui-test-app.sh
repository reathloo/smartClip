#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
  export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
swift build
app=".build/SmartClip Test.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/debug/SmartClip "$app/Contents/MacOS/SmartClip"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
resource_bundle=".build/debug/SmartClip_SmartClip.bundle"
[[ -d "$resource_bundle" ]] || { echo "Missing localization bundle: $resource_bundle" >&2; exit 1; }
if [[ -d "$resource_bundle/Contents/Resources" ]]; then
  localization_root="$resource_bundle/Contents/Resources"
else
  localization_root="$resource_bundle"
fi
for language in en de zh-Hans ja ko; do
  localization="$localization_root/$language.lproj"
  [[ -d "$localization" ]] || { echo "Missing localization resources: $localization" >&2; exit 1; }
  cp -R "$localization" "$app/Contents/Resources/"
done
zsh scripts/embed-sparkle.sh debug "$app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.smartclip.UITest' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName SmartClip Test' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName SmartClip Test' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :SmartClipUITest bool true' "$app/Contents/Info.plist"
codesign --force --deep --sign - "$app"
echo "Built $app (synthetic fixtures, separate clipboard, no system integrations)"
