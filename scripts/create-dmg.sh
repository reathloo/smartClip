#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
source_dir="${1:-}"
output="${2:-}"
release_version="${3:-}"

if [[ -z "$source_dir" || -z "$output" ]]; then
  print -u2 "Usage: zsh scripts/create-dmg.sh <source-directory> <output.dmg> [release-version]"
  exit 1
fi

source_dir="${source_dir:A}"
output="${output:A}"
app="$source_dir/SmartClip.app"
background="$root/Resources/DMGBackground.png"
[[ -d "$app" ]] || { print -u2 "SmartClip.app is missing: $app"; exit 1; }
[[ -f "$background" ]] || { print -u2 "DMG background is missing: $background"; exit 1; }
app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
volume_name="SmartClip ${release_version:-$app_version}"

python=""
for candidate in python3.13 python3.12 python3.11 python3.10 python3; do
  candidate_path="$(command -v "$candidate" 2>/dev/null || true)"
  if [[ -n "$candidate_path" ]] && "$candidate_path" -c 'import sys; raise SystemExit(sys.version_info < (3, 10))'; then
    python="$candidate_path"
    break
  fi
done
[[ -n "$python" ]] || {
  print -u2 "Creating the styled DMG requires Python 3.10 or newer."
  exit 1
}

tools="$root/.build/release-tools-1.6.7"
if [[ ! -x "$tools/bin/dmgbuild" ]]; then
  "$python" -m venv "$tools"
  "$tools/bin/python" -m pip install --quiet --disable-pip-version-check 'dmgbuild==1.6.7'
fi

rm -f "$output"
"$tools/bin/dmgbuild" \
  -s "$root/scripts/dmg-settings.py" \
  -D "app=$app" \
  -D "background=$background" \
  "$volume_name" "$output"
/usr/bin/hdiutil verify "$output" >/dev/null
print "Created styled DMG: $output"
