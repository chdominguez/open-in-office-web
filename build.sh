#!/bin/zsh
# Builds "Open in Office Web.app" into build/.
#   ./build.sh            universal build (Apple Silicon + Intel)
#   ./build.sh --install  also copies it to ~/Applications
#   ARCHS=arm64 ./build.sh   faster single-architecture build
#   SIGN_IDENTITY="Developer ID Application: …" ./build.sh   sign for distribution (default: ad-hoc)
set -euo pipefail
cd "${0:A:h}"

NAME="Open in Office Web"
APP="build/$NAME.app"
HELPER="$APP/Contents/Helpers/$NAME Sync.app"
EXE=OpenInOfficeWeb
ARCHS=(${=ARCHS:-arm64 x86_64})
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

rm -rf build && mkdir -p build "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents" "$HELPER/Contents/MacOS"

slices=()
for arch in $ARCHS; do
  swiftc -O -swift-version 5 -target "$arch-apple-macosx13.0" Sources/*.swift -o "build/$EXE-$arch"
  slices+=("build/$EXE-$arch")
done
lipo -create $slices -output "$APP/Contents/MacOS/$EXE"

swift scripts/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP/Contents/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
cp Resources/io.github.chdominguez.OpenInOfficeWeb.Sync.plist "$APP/Contents/Library/LaunchAgents/"

# Sync helper: same executable in its own bundle, so macOS never hands it the documents
# the user opens, and it runs without a Dock icon.
cp "$APP/Contents/MacOS/$EXE" "$HELPER/Contents/MacOS/"
cp -R "$APP/Contents/Resources" "$HELPER/Contents/"
cp Resources/Info.plist "$HELPER/Contents/"
PB=/usr/libexec/PlistBuddy
$PB -c "Set :CFBundleIdentifier io.github.chdominguez.OpenInOfficeWeb.Sync" \
    -c "Set :CFBundleName $NAME Sync" \
    -c "Set :CFBundleDisplayName $NAME Sync" \
    -c "Delete :CFBundleDocumentTypes" \
    -c "Add :LSUIElement bool true" "$HELPER/Contents/Info.plist"
rm -f "$HELPER/Contents/Resources/"*.lproj/InfoPlist.strings

sign_opts=(--force --sign "$SIGN_IDENTITY")
[[ "$SIGN_IDENTITY" != "-" ]] && sign_opts+=(--options runtime --timestamp)
codesign $sign_opts "$HELPER"
codesign $sign_opts "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/$EXE"))"

if [[ "${1:-}" == "--install" ]]; then
  DEST="$HOME/Applications/$NAME.app"
  mkdir -p "$HOME/Applications" && rm -rf "$DEST" && cp -R "$APP" "$DEST"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
  echo "Installed $DEST"
fi
