#!/bin/zsh
# bundle.sh — build HorizonXI-on-Mac.app from the SPM executable.
# No Xcode required; this machine only has the Command Line Tools.
set -euo pipefail

HERE="${0:A:h}"
REPO="${HERE:h}"
OUT="${1:-$HERE/build}"
APP="$OUT/HorizonXI-on-Mac.app"

cd "$HERE"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/HorizonXILauncher"
[[ -x "$BIN" ]] || { echo "build produced no binary" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/HorizonXI-on-Mac"

# install.sh + its helper are the Repair action; ship them inside the bundle.
cp "$REPO/scripts/install.sh"        "$APP/Contents/Resources/install.sh"
cp "$REPO/scripts/fix-wine-rpath.sh" "$APP/Contents/Resources/fix-wine-rpath.sh"
chmod +x "$APP/Contents/Resources/"*.sh

# The Metal/DXVK renderer ships inside the app: Renderer.swift resolves these by name out of
# Bundle.main, so the user never has to fetch a DLL by hand.
for dll in d3d8to9.dll dxvk-1.10.3-x32-d3d9-horizonxi.dll; do
  [[ -f "$REPO/vendor/$dll" ]] && cp "$REPO/vendor/$dll" "$APP/Contents/Resources/$dll"
done

# Dock/Finder icon: the FFXI Vana'diel sphere, lifted from the icon resources of the game's own
# DONTTOUCH_Registry.exe (the only 256px source on disk) and upscaled into a full .icns.
[[ -f "$HERE/AppIcon.icns" ]] && cp "$HERE/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>HorizonXI on Mac</string>
  <key>CFBundleDisplayName</key><string>HorizonXI on Mac</string>
  <key>CFBundleExecutable</key><string>HorizonXI-on-Mac</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>org.batesai.horizonxi-on-mac</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.2</string>
  <key>CFBundleVersion</key><string>3</string>
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

echo "built $APP"
