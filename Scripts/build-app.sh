#!/bin/zsh
# Builds Starlist.app from the Swift package. Needs only the Xcode Command Line Tools.
#
#   Scripts/build-app.sh             Build into build/Starlist.app
#   Scripts/build-app.sh --install   Build, copy to /Applications, and launch it
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)"

APP="build/Starlist.app"
ICONSET="build/AppIcon.iconset"
rm -rf "$APP" "$ICONSET"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/Starlist" "$APP/Contents/MacOS/Starlist"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# The icon is drawn in code; render every size and pack them into an .icns.
"$BIN/starlist-dev" icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# Ad-hoc signature: enough to run on this Mac.
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  DEST="/Applications/Starlist.app"
  # Quit a running copy so the new one can take its place.
  osascript -e 'tell application id "com.kaitlyn.Starlist" to quit' >/dev/null 2>&1 || true
  sleep 1
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  open "$DEST"
  echo "Installed and launched $DEST"
fi
