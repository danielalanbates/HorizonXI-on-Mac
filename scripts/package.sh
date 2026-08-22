#!/bin/zsh
# package.sh — build a distributable disk image of the launcher.
#
#   ./scripts/package.sh [output-dir]
#
# What ships in the .dmg:
#   FFXI-on-Mac.app   the launcher (preflight, repair, account, play, renderer)
#                          — the DXVK + d3d8to9 DLLs ride inside it, so the Metal
#                            renderer needs no separate download
#   START HERE.md          the non-technical setup guide
#
# What does NOT ship, and why:
#   * The game client (15-30 GB, per world) — it is Square Enix's data and may not be
#     redistributed. The launcher fetches it with one *Download...* button per world.
#   * The Wine wrapper (~1GB+) — Sikarugir wine is LGPL 2.1 and may be redistributed, but doing
#     it properly means carrying the LGPL's source/relink obligations, so the launcher fetches
#     it from Sikarugir's own releases and assembles it on the user's Mac (*Install wine...*).
#
# So the 5 MB image is the launcher, and the launcher gets the other two itself. Nothing here
# leaves the user at a Terminal prompt.
set -euo pipefail

HERE="${0:A:h}"
REPO="${HERE:h}"
OUT="${1:-$REPO/dist}"
STAGE="$(mktemp -d)"
# Build first, then read the version -- otherwise the DMG is named after the previous build.
# Build somewhere outside the checkout: when the checkout is in iCloud, codesign refuses the
# bundle over the extended attributes iCloud attaches to it mid-build.
BUILDDIR="$(mktemp -d)"
"$REPO/app/bundle.sh" "$BUILDDIR" >/dev/null
APP="$BUILDDIR/FFXI-on-Mac.app"
VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw \
    "$APP/Contents/Info.plist" 2>/dev/null || echo 1.0)"
DMG="$OUT/FFXI-on-Mac-$VERSION.dmg"

mkdir -p "$OUT"

# Notarise and staple the .app BEFORE it goes into the image. Stapling the disk image alone is
# not enough: an app dragged out of it carries no ticket of its own, so the first launch has to
# ask Apple over the network and fails closed if the machine is offline.
if [[ -n "${HXI_SIGN_ID:-}" ]]; then
  PROFILE="${HXI_NOTARY_PROFILE:-batesai-notary}"
  echo "notarising the app (a few minutes)"
  ditto -c -k --keepParent "$APP" "$BUILDDIR/app.zip"
  xcrun notarytool submit "$BUILDDIR/app.zip" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP"
fi

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$REPO/README.md"     "$STAGE/README.md"
cp "$REPO/docs/SETUP.md" "$STAGE/START HERE.md"

rm -f "$DMG"
hdiutil create -quiet -volname "FFXI on Mac" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE" "$BUILDDIR"

echo "built $DMG"

# Signing and notarising used to be a block of instructions printed here for a human to follow.
# Nobody followed them exactly, and the result shipped unnotarised, so the script does it.
#
# Set HXI_SIGN_ID to the Developer ID certificate's SHA-1 hash -- the *hash*, not the name, since
# there are several identically named "Developer ID Application: Daniel Bates" certs in the
# keychain and codesign calls the name ambiguous. HXI_NOTARY_PROFILE is a notarytool keychain
# profile (`xcrun notarytool store-credentials`); it defaults to batesai-notary.
#
# Do NOT add --timestamp to codesign here: it hangs indefinitely on this network. The notary
# service supplies its own trusted timestamp, so the ticket is valid without it.
if [[ -z "${HXI_SIGN_ID:-}" ]]; then
  echo
  echo "NOT signed or notarised -- this build is blocked by Gatekeeper on every other Mac."
  echo "Re-run with HXI_SIGN_ID=<developer-id-cert-sha1> to sign, notarise and staple."
  exit 0
fi

echo "signing the disk image"
codesign --force -s "$HXI_SIGN_ID" "$DMG"

echo "submitting to Apple's notary service (a few minutes)"
if ! xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait; then
  echo "notarisation FAILED -- get the reason with:" >&2
  echo "  xcrun notarytool log <submission-id> --keychain-profile $PROFILE" >&2
  exit 1
fi

xcrun stapler staple "$DMG"

echo
echo "verifying as Gatekeeper sees it"
spctl -a -t open --context context:primary-signature -v "$DMG"
