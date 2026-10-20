#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
cd "$root"

release_tag="${1:-v0.1.0-beta.1}"
if [[ ! "$release_tag" =~ '^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$' ]]; then
  print -u2 "Ungültige Version: $release_tag (erwartet z. B. v0.1.0-beta.1)"
  exit 1
fi

release_version="${release_tag#v}"
app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)"
if [[ "$release_version" != "$app_version" && "$release_version" != "$app_version"-* ]]; then
  print -u2 "Release $release_version passt nicht zur App-Version $app_version."
  exit 1
fi

zsh scripts/test.sh
zsh scripts/build-app.sh

app="dist/SmartClip.app"
binary="$app/Contents/MacOS/SmartClip"
/usr/bin/codesign --verify --deep --strict "$app"
/usr/bin/plutil -lint "$app/Contents/Info.plist" >/dev/null

architectures="$(/usr/bin/lipo -archs "$binary")"
case " $architectures " in
  *" arm64 "*" x86_64 "*) platform="universal" ;;
  *" arm64 "*) platform="arm64" ;;
  *)
    print -u2 "Nicht unterstützte Architektur: $architectures"
    exit 1
    ;;
esac

release_dir="$root/dist/release"
asset_base="SmartClip-${release_version}-macOS-${platform}"
dmg="$release_dir/$asset_base.dmg"
checksum="$dmg.sha256"
manifest="$release_dir/$asset_base.txt"
stage="$(mktemp -d "${TMPDIR:-/tmp}/smartclip-release.XXXXXX")"
trap 'rm -rf "$stage"' EXIT

rm -rf "$release_dir"
mkdir -p "$release_dir" "$stage/SmartClip"
/usr/bin/ditto --noqtn "$app" "$stage/SmartClip/SmartClip.app"
/bin/ln -s /Applications "$stage/SmartClip/Programme"
/bin/cat > "$stage/SmartClip/Installationshinweise.txt" <<'EOF'
SMARTCLIP INSTALLIEREN

1. SmartClip.app auf „Programme“ ziehen.
2. SmartClip in Programme einmal öffnen.
3. Nach der macOS-Warnung Systemeinstellungen > Datenschutz & Sicherheit öffnen.
4. Bei SmartClip auf „Dennoch öffnen“ und anschließend auf „Öffnen“ klicken.

SmartClip ist nicht mit einer kostenpflichtigen Apple Developer ID signiert und
nicht notarisiert. Lade das Paket nur aus dem offiziellen SmartClip-Release.
EOF

/usr/bin/hdiutil create -quiet -ov -format UDZO -volname "SmartClip" \
  -srcfolder "$stage/SmartClip" "$dmg"
/usr/bin/hdiutil verify "$dmg" >/dev/null

(
  cd "$release_dir"
  /usr/bin/shasum -a 256 "${dmg:t}" > "${checksum:t}"
)

commit="$(git rev-parse HEAD)"
if [[ -n "$(git status --porcelain)" ]]; then source_state="lokale Änderungen vorhanden"
else source_state="sauber"; fi
cat > "$manifest" <<EOF
SmartClip $release_tag
App-Version: $app_version ($build_number)
System: macOS 14 oder neuer
Architektur: $architectures
Signatur: ad hoc (keine Apple Developer ID)
Notarisierung: nein
Git-Commit: $commit
Quellzustand: $source_state
SHA-256: $(awk '{print $1}' "$checksum")
EOF

zsh scripts/verify-release.sh "$dmg"

print ""
print "Release-Paket erstellt:"
print "  $dmg"
print "  $checksum"
print "  $manifest"
