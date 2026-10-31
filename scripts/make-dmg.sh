#!/bin/zsh
# Builds the app and packages it as dist/OpenInOfficeWeb-<version>.dmg.
# With SIGN_IDENTITY and NOTARY_PROFILE (an `xcrun notarytool store-credentials` profile)
# set, the DMG is also notarized and stapled.
set -euo pipefail
cd "${0:A:h}/.."

./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
DMG="dist/OpenInOfficeWeb-$VERSION.dmg"
STAGE=build/dmg

rm -rf "$STAGE" && mkdir -p "$STAGE" dist && rm -f "$DMG"
cp -R "build/Open in Office Web.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Open in Office Web" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi
shasum -a 256 "$DMG"
