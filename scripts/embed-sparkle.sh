#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
configuration="${1:-}"
app="${2:-}"

if [[ -z "$configuration" || -z "$app" ]]; then
  print -u2 "Usage: zsh scripts/embed-sparkle.sh <debug|release> <App.app>"
  exit 1
fi

framework="$root/.build/$configuration/Sparkle.framework"
[[ -d "$framework" ]] || {
  print -u2 "Sparkle framework is missing: $framework"
  exit 1
}

mkdir -p "$app/Contents/Frameworks"
/usr/bin/ditto "$framework" "$app/Contents/Frameworks/Sparkle.framework"
mkdir -p "$app/Contents/Resources/ThirdPartyLicenses"
/usr/bin/ditto "$root/.build/artifacts/sparkle/Sparkle/LICENSE" \
  "$app/Contents/Resources/ThirdPartyLicenses/Sparkle.txt"
