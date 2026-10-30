#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
cd "$root"

command -v gh >/dev/null || { print -u2 "GitHub CLI is required."; exit 1; }
gh auth status >/dev/null
swift package resolve

tool="$root/.build/artifacts/sparkle/Sparkle/bin/generate_keys"
[[ -x "$tool" ]] || { print -u2 "Sparkle generate_keys is missing."; exit 1; }

expected="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Resources/Info.plist)"
actual="$("$tool" --account dev.smartclip.SmartClip -p)"
[[ "$actual" == "$expected" ]] || {
  print -u2 "The Keychain key does not match SUPublicEDKey in Resources/Info.plist."
  exit 1
}

secret_directory="$(mktemp -d "${TMPDIR:-/tmp}/smartclip-sparkle-key.XXXXXX")"
chmod 700 "$secret_directory"
secret_file="$secret_directory/private-key"
cleanup() { rm -f "$secret_file"; rmdir "$secret_directory"; }
trap cleanup EXIT

"$tool" --account dev.smartclip.SmartClip -x "$secret_file" >/dev/null
gh secret set SPARKLE_PRIVATE_KEY --repo reathloo/smartClip < "$secret_file"
print "Configured SPARKLE_PRIVATE_KEY for reathloo/smartClip without printing it."
