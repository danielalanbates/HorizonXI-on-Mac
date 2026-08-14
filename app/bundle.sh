#!/bin/zsh
# bundle.sh — build FFXI-on-Mac.app from the SPM executable.
# No Xcode required; this machine only has the Command Line Tools.
set -euo pipefail

HERE="${0:A:h}"
REPO="${HERE:h}"
OUT="${1:-$HERE/build}"
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
  <key>CFBundleShortVersionString</key><string>2.5</string>
  <key>CFBundleVersion</key><string>6</string>
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
if [[ -n "${HXI_SIGN_ID:-}" ]]; then
  codesign --force --deep --options runtime -s "$HXI_SIGN_ID" "$APP"
else
  codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true
fi

# Deep-signing the app just now re-signed x87sidecar_entitled with the app's own (empty)
# entitlements, which silently breaks its ability to attach to another process. Re-sign it last,
# on its own, with the entitlements it actually needs -- must come after the block above, not
# before, or --deep overwrites this instead.
X87SC="$APP/Contents/Resources/x87sidecar_entitled"
if [[ -f "$X87SC" ]]; then
  if [[ -n "${HXI_SIGN_ID:-}" ]]; then
    codesign --force --options runtime -s "$HXI_SIGN_ID" \
      --entitlements "$REPO/vendor/x87sidecar-entitlements.plist" "$X87SC"
  else
    codesign --force -s - \
      --entitlements "$REPO/vendor/x87sidecar-entitlements.plist" "$X87SC" >/dev/null 2>&1 || true
  fi
fi

# Re-register with Launch Services. Replacing a bundle in place leaves the Dock and Finder
# showing the icon they cached for that path -- after a rebuild the app came up with the generic
# executable icon even though AppIcon.icns was present and complete.
touch "$APP"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[[ -x "$LSREG" ]] && "$LSREG" -f "$APP" >/dev/null 2>&1 || true

echo "built $APP"
