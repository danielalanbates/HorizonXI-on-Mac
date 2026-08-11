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
for dll in d3d8to9.dll dxvk-1.10.3-x32-d3d9.dll dxvk-1.10.3-x32-d3d9-nofog.dll; do
  [[ -f "$REPO/vendor/$dll" ]] && cp "$REPO/vendor/$dll" "$APP/Contents/Resources/$dll"
done

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>HorizonXI on Mac</string>
  <key>CFBundleDisplayName</key><string>HorizonXI on Mac</string>
  <key>CFBundleExecutable</key><string>HorizonXI-on-Mac</string>
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

# Ad-hoc signature. Do NOT pass --timestamp here: it hangs on this network.
codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true

echo "built $APP"
