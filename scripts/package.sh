#!/bin/zsh
# package.sh — build a distributable disk image of the launcher.
#
#   ./scripts/package.sh [output-dir]
#
# What ships in the .dmg:
#   HorizonXI-on-Mac.app   the launcher (preflight, repair, account, play, renderer)
#                          — the DXVK + d3d8to9 DLLs ride inside it, so the Metal
#                            renderer needs no separate download
#   START HERE.md          the non-technical setup guide
#
# What does NOT ship, and why:
#   * The HorizonXI client (~27GB) — it is Square Enix's game data. Users install it with
#     HorizonXI's own Windows launcher or by copying an existing install.
#   * The Wine wrapper (~1GB+) — redistributing a CrossOver-derived build has licence
#     implications this project has not cleared. The launcher points at a wrapper you supply.
#
# So this is a launcher package, not a one-click "install everything" bundle. Making it one
# requires a first-run downloader for both of the above; that work is not done.
set -euo pipefail

HERE="${0:A:h}"
REPO="${HERE:h}"
OUT="${1:-$REPO/dist}"
STAGE="$(mktemp -d)"
# Build first, then read the version -- otherwise the DMG is named after the previous build.
"$REPO/app/bundle.sh" >/dev/null
VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw \
    "$REPO/app/build/HorizonXI-on-Mac.app/Contents/Info.plist" 2>/dev/null || echo 1.0)"
DMG="$OUT/HorizonXI-on-Mac-$VERSION.dmg"

mkdir -p "$OUT"
cp -R "$REPO/app/build/HorizonXI-on-Mac.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$REPO/README.md"     "$STAGE/README.md"
cp "$REPO/docs/SETUP.md" "$STAGE/START HERE.md"

rm -f "$DMG"
hdiutil create -quiet -volname "HorizonXI on Mac" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "built $DMG"
echo
echo "To ship it, sign and notarise — an unsigned build is blocked on every other Mac:"
echo
echo "  # do this OUTSIDE iCloud. iCloud attaches extended attributes and codesign refuses"
echo "  # with 'resource fork, Finder information, or similar detritus not allowed'."
echo "  ditto --norsrc --noextattr --noacl <app> /tmp/pkg/HorizonXI-on-Mac.app"
echo "  codesign --force --deep --options runtime --timestamp \\"
echo "      -s 'Developer ID Application: ...' /tmp/pkg/HorizonXI-on-Mac.app"
echo "  # ^ pass the certificate SHA-1, not the name, if two Developer ID certs are installed"
echo "  hdiutil create ... && codesign --force --timestamp -s '...' <dmg>"
echo "  xcrun notarytool submit <dmg> --keychain-profile batesai-notary --wait"
echo "  xcrun stapler staple <dmg>"
echo
echo "Verify with: spctl -a -t open --context context:primary-signature -v <dmg>"
echo "Expect: 'accepted / source=Notarized Developer ID'."
