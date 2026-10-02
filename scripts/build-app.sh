#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
  export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
swift build -c release
app="dist/SmartClip.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/SmartClip "$app/Contents/MacOS/SmartClip"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
echo "Built $app"
