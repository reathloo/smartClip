#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
tag="${1:-}"
dmg="${2:-}"
output="${3:-$root/dist/update-feed/appcast.xml}"

if [[ ! "$tag" =~ '^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$' || -z "$dmg" ]]; then
  print -u2 "Usage: zsh scripts/generate-appcast.sh <vX.Y.Z> <SmartClip.dmg> [output.xml]"
  exit 1
fi

dmg="${dmg:A}"
[[ -f "$dmg" ]] || { print -u2 "DMG is missing: $dmg"; exit 1; }
sign_tool="$root/.build/artifacts/sparkle/Sparkle/bin/sign_update"
[[ -x "$sign_tool" ]] || { print -u2 "Sparkle sign_update is missing. Run swift package resolve."; exit 1; }

if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  signed="$(print -rn -- "$SPARKLE_PRIVATE_KEY" | "$sign_tool" --ed-key-file - "$dmg")"
else
  key_tool="$root/.build/artifacts/sparkle/Sparkle/bin/generate_keys"
  key_directory="$(mktemp -d "${TMPDIR:-/tmp}/smartclip-appcast-key.XXXXXX")"
  chmod 700 "$key_directory"
  temporary_key="$key_directory/private-key"
  cleanup_key() { rm -f "$temporary_key"; rmdir "$key_directory"; }
  trap cleanup_key EXIT
  "$key_tool" --account dev.smartclip.SmartClip -x "$temporary_key" >/dev/null
  signed="$("$sign_tool" --ed-key-file "$temporary_key" "$dmg")"
fi

signature="${signed#*sparkle:edSignature=\"}"
signature="${signature%%\"*}"
length="${signed#*length=\"}"
length="${length%%\"*}"
[[ -n "$signature" && "$length" == <-> ]] || {
  print -u2 "Could not read Sparkle signature metadata: $signed"
  exit 1
}

if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  print -rn -- "$SPARKLE_PRIVATE_KEY" | \
    "$sign_tool" --ed-key-file - --verify "$dmg" "$signature" >/dev/null
else
  "$sign_tool" --ed-key-file "$temporary_key" --verify "$dmg" "$signature" >/dev/null
  cleanup_key
  trap - EXIT
fi

release_version="${tag#v}"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$root/Resources/Info.plist")"
asset="${dmg:t}"
download_url="https://github.com/reathloo/smartClip/releases/download/$tag/$asset"
release_url="https://github.com/reathloo/smartClip/releases/tag/$tag"
published="$(LC_ALL=C /bin/date -u '+%a, %d %b %Y %H:%M:%S +0000')"

mkdir -p "${output:h}"
{
  print '<?xml version="1.0" encoding="utf-8"?>'
  print '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
  print '  <channel>'
  print '    <title>SmartClip Updates</title>'
  print '    <link>https://github.com/reathloo/smartClip</link>'
  print '    <description>Signed SmartClip releases for macOS.</description>'
  print '    <language>en</language>'
  print '    <item>'
  print "      <title>SmartClip $release_version</title>"
  print "      <link>$release_url</link>"
  print "      <sparkle:releaseNotesLink>$release_url</sparkle:releaseNotesLink>"
  print "      <pubDate>$published</pubDate>"
  print "      <sparkle:version>$build_number</sparkle:version>"
  print "      <sparkle:shortVersionString>$release_version</sparkle:shortVersionString>"
  print '      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>'
  print '      <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>'
  print "      <enclosure url=\"$download_url\" length=\"$length\" type=\"application/octet-stream\" sparkle:edSignature=\"$signature\" />"
  print '    </item>'
  print '  </channel>'
  print '</rss>'
} > "$output"

/usr/bin/plutil -lint "$root/Resources/Info.plist" >/dev/null
print "Generated signed Sparkle appcast: $output"
