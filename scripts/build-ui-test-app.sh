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
zsh scripts/embed-sparkle.sh debug "$app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.smartclip.UITest' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName SmartClip Test' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName SmartClip Test' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :SmartClipUITest bool true' "$app/Contents/Info.plist"
codesign --force --deep --sign - "$app"
echo "Built $app (synthetic fixtures, separate clipboard, no system integrations)"
