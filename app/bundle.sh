#!/bin/zsh
# bundle.sh — build FFXI-on-Mac.app from the SPM executable.
# No Xcode required; this machine only has the Command Line Tools.
set -euo pipefail

HERE="${0:A:h}"
REPO="${HERE:h}"
# Default output is beside the sources, except when the checkout lives in iCloud Drive: iCloud
# re-adds extended attributes to files while they are being written, and codesign refuses any
# bundle carrying them ("resource fork, Finder information, or similar detritus not allowed").
# Stripping them does not help -- they come back mid-build -- so build somewhere else entirely.
if [[ -n "${1:-}" ]]; then
  OUT="$1"
elif [[ "$HERE" == *"/Mobile Documents/"* ]]; then
  OUT="${TMPDIR:-/tmp}/ffxi-on-mac-build"
else
  OUT="$HERE/build"
fi
APP="$OUT/FFXI-on-Mac.app"

cd "$HERE"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/HorizonXILauncher"
[[ -x "$BIN" ]] || { echo "build produced no binary" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FFXI-on-Mac"

# install.sh + its helper are the Repair action; lsb-server.sh is the whole local-server world
# (dependencies, source, database, build, run). All three are run out of the bundle.
cp "$REPO/scripts/install.sh"        "$APP/Contents/Resources/install.sh"
cp "$REPO/scripts/fix-wine-rpath.sh" "$APP/Contents/Resources/fix-wine-rpath.sh"
cp "$REPO/scripts/lsb-server.sh"     "$APP/Contents/Resources/lsb-server.sh"
cp "$REPO/scripts/update-client.sh"  "$APP/Contents/Resources/update-client.sh"
chmod +x "$APP/Contents/Resources/"*.sh

# The Metal/DXVK renderer ships inside the app: Renderer.swift resolves these by name out of
# Bundle.main, so the user never has to fetch a DLL by hand.
for dll in d3d8to9.dll dxvk-1.10.3-x32-d3d9-horizonxi.dll; do
  [[ -f "$REPO/vendor/$dll" ]] && cp "$REPO/vendor/$dll" "$APP/Contents/Resources/$dll"
done

# x87sidecar: the fix for FFXI's x87 floating-point math running ~100x slow under Rosetta (see
# docs/X87-WALL.md). Signed individually below with its own entitlements -- the app's deep-sign
# strips them otherwise, and without get-task-allow/cs.debugger it cannot attach to the game.
if [[ -f "$REPO/vendor/x87sidecar_entitled" ]]; then
  cp "$REPO/vendor/x87sidecar_entitled" "$APP/Contents/Resources/x87sidecar_entitled"
  chmod +x "$APP/Contents/Resources/x87sidecar_entitled"
fi

# Dock/Finder icon: an original crystal mark in the launcher's own Vana'diel palette (see
# scripts/make_icon.py), not extracted from Square Enix's client -- this project's own art.
[[ -f "$HERE/AppIcon.icns" ]] && cp "$HERE/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>FFXI on Mac</string>
  <key>CFBundleDisplayName</key><string>FFXI on Mac</string>
  <key>CFBundleExecutable</key><string>FFXI-on-Mac</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>org.batesai.horizonxi-on-mac</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.6</string>
  <key>CFBundleVersion</key><string>7</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
</dict>
</plist>
PLIST

# Signature. Ad-hoc by default; set HXI_SIGN_ID to a Developer ID hash for a release build
# that can be notarised. Use the certificate *hash*, not its name -- there are two identical
# "Developer ID Application: Daniel Bates" certs in the login keychain and codesign rejects
# the name as ambiguous. Do NOT pass --timestamp here: it hangs on this network.
# Order matters, and the obvious order is wrong. x87sidecar_entitled needs its own entitlements
# (get-task-allow, cs.debugger) or it cannot attach to the game at all. Signing it *after* the
# app breaks the app's seal -- `codesign -v` then reports "a sealed resource is missing or
# invalid" and Gatekeeper rejects the bundle. So sign the nested binary FIRST, then sign the app
# WITHOUT --deep, which leaves nested signatures alone and seals them as they are.
#
# iCloud puts xattrs on everything it syncs and codesign refuses to sign a bundle carrying them
# ("resource fork, Finder information, or similar detritus not allowed"), so strip them first.
find "$APP" -exec xattr -c {} \; 2>/dev/null || true

X87SC="$APP/Contents/Resources/x87sidecar_entitled"
if [[ -n "${HXI_SIGN_ID:-}" ]]; then
  [[ -f "$X87SC" ]] && codesign --force --options runtime -s "$HXI_SIGN_ID" \
    --entitlements "$REPO/vendor/x87sidecar-entitlements.plist" "$X87SC"
  codesign --force --options runtime -s "$HXI_SIGN_ID" "$APP"
else
  [[ -f "$X87SC" ]] && codesign --force -s - \
    --entitlements "$REPO/vendor/x87sidecar-entitlements.plist" "$X87SC" >/dev/null 2>&1 || true
  codesign --force -s - "$APP" >/dev/null 2>&1 || true
fi

# Re-register with Launch Services. Replacing a bundle in place leaves the Dock and Finder
# showing the icon they cached for that path -- after a rebuild the app came up with the generic
# executable icon even though AppIcon.icns was present and complete.
touch "$APP"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[[ -x "$LSREG" ]] && "$LSREG" -f "$APP" >/dev/null 2>&1 || true

echo "built $APP"
