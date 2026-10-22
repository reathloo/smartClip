#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
dmg="${1:-}"
if [[ -z "$dmg" ]]; then
  print -u2 "Usage: zsh scripts/verify-release.sh <SmartClip.dmg>"
  exit 1
fi
dmg="${dmg:A}"
checksum="$dmg.sha256"

[[ -f "$dmg" ]] || { print -u2 "DMG is missing: $dmg"; exit 1; }
[[ -f "$checksum" ]] || { print -u2 "Checksum is missing: $checksum"; exit 1; }

(
  cd "${dmg:h}"
  /usr/bin/shasum -a 256 -c "${checksum:t}"
)
/usr/bin/hdiutil verify "$dmg" >/dev/null

work="$(mktemp -d "${TMPDIR:-/tmp}/smartclip-verify.XXXXXX")"
mount="$work/mount"
installed="$work/SmartClip.app"
mkdir -p "$mount"
mounted=false
cleanup() {
  if $mounted; then /usr/bin/hdiutil detach "$mount" -quiet || true; fi
  rm -rf "$work"
}
trap cleanup EXIT

/usr/bin/hdiutil attach -quiet -readonly -nobrowse -mountpoint "$mount" "$dmg"
mounted=true
app="$mount/SmartClip.app"
[[ -d "$app" ]] || { print -u2 "SmartClip.app is missing from the DMG"; exit 1; }
[[ -L "$mount/Applications" && "$(readlink "$mount/Applications")" == "/Applications" ]] || {
  print -u2 "Applications link is missing from the DMG"
  exit 1
}

/usr/bin/codesign --verify --deep --strict "$app"
/usr/bin/plutil -lint "$app/Contents/Info.plist" >/dev/null
minimum="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist")"
[[ "$minimum" == "14.0" ]] || { print -u2 "Unexpected minimum version: $minimum"; exit 1; }
/usr/bin/file "$app/Contents/MacOS/SmartClip" | /usr/bin/grep -q 'arm64'

# Simulate a browser download. Gatekeeper must reject this intentionally
# unnotarized package; users then allow it explicitly in System Settings.
/usr/bin/ditto "$app" "$installed"
/usr/bin/xattr -w com.apple.quarantine "0083;$(printf '%x' $(date +%s));SmartClipReleaseTest;" "$installed"
assessment="$(/usr/sbin/spctl --assess --type execute --verbose=2 "$installed" 2>&1 || true)"
if [[ "$assessment" != *"rejected"* ]]; then
  print -u2 "Gatekeeper did not return the expected rejection: $assessment"
  exit 1
fi

print "Package verification passed: app, DMG, checksum, architecture, and expected Gatekeeper warning."
