#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
dmg="${1:-}"
if [[ -z "$dmg" ]]; then
  print -u2 "Aufruf: zsh scripts/verify-release.sh <SmartClip.dmg>"
  exit 1
fi
dmg="${dmg:A}"
checksum="$dmg.sha256"

[[ -f "$dmg" ]] || { print -u2 "DMG fehlt: $dmg"; exit 1; }
[[ -f "$checksum" ]] || { print -u2 "Prüfsumme fehlt: $checksum"; exit 1; }

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
[[ -d "$app" ]] || { print -u2 "SmartClip.app fehlt im DMG"; exit 1; }
[[ -L "$mount/Programme" && "$(readlink "$mount/Programme")" == "/Applications" ]] || {
  print -u2 "Programme-Verknüpfung fehlt im DMG"
  exit 1
}

/usr/bin/codesign --verify --deep --strict "$app"
/usr/bin/plutil -lint "$app/Contents/Info.plist" >/dev/null
minimum="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist")"
[[ "$minimum" == "14.0" ]] || { print -u2 "Unerwartete Mindestversion: $minimum"; exit 1; }
/usr/bin/file "$app/Contents/MacOS/SmartClip" | /usr/bin/grep -q 'arm64'

# Simuliert einen Browser-Download. Bei diesem bewusst nicht notarisierten Paket
# muss Gatekeeper ablehnen; Nutzer öffnen es danach gezielt über die Systemeinstellungen.
/usr/bin/ditto "$app" "$installed"
/usr/bin/xattr -w com.apple.quarantine "0083;$(printf '%x' $(date +%s));SmartClipReleaseTest;" "$installed"
assessment="$(/usr/sbin/spctl --assess --type execute --verbose=2 "$installed" 2>&1 || true)"
if [[ "$assessment" != *"rejected"* ]]; then
  print -u2 "Gatekeeper lieferte nicht die erwartete Ablehnung: $assessment"
  exit 1
fi

print "Paketprüfung bestanden: App, DMG, Prüfsumme, Architektur und erwartete Gatekeeper-Warnung."
