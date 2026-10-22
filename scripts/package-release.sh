#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
cd "$root"

release_tag="${1:-v0.1.0-beta.1}"
if [[ ! "$release_tag" =~ '^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$' ]]; then
  print -u2 "Invalid version: $release_tag (expected, for example, v0.1.0-beta.1)"
  exit 1
fi

release_version="${release_tag#v}"
app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)"
if [[ "$release_version" != "$app_version" && "$release_version" != "$app_version"-* ]]; then
  print -u2 "Release $release_version does not match app version $app_version."
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
    print -u2 "Unsupported architecture: $architectures"
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
/bin/ln -s /Applications "$stage/SmartClip/Applications"
/bin/cat > "$stage/SmartClip/Installation Instructions.txt" <<'EOF'
INSTALL SMARTCLIP

1. Drag SmartClip.app to Applications.
2. Open SmartClip once from Applications.
3. After the macOS warning, open System Settings > Privacy & Security.
4. Choose Open Anyway for SmartClip, then choose Open.

SmartClip is not signed with an Apple Developer ID and is not notarized.
Download the package only from the official SmartClip release.
EOF

/usr/bin/hdiutil create -quiet -ov -format UDZO -volname "SmartClip" \
  -srcfolder "$stage/SmartClip" "$dmg"
/usr/bin/hdiutil verify "$dmg" >/dev/null

(
  cd "$release_dir"
  /usr/bin/shasum -a 256 "${dmg:t}" > "${checksum:t}"
)

commit="$(git rev-parse HEAD)"
if [[ -n "$(git status --porcelain)" ]]; then source_state="local changes present"
else source_state="clean"; fi
cat > "$manifest" <<EOF
SmartClip $release_tag
App version: $app_version ($build_number)
System: macOS 14 or newer
Architecture: $architectures
Signature: ad hoc (no Apple Developer ID)
Notarized: no
Git commit: $commit
Source state: $source_state
SHA-256: $(awk '{print $1}' "$checksum")
EOF

zsh scripts/verify-release.sh "$dmg"

print ""
print "Release package created:"
print "  $dmg"
print "  $checksum"
print "  $manifest"
