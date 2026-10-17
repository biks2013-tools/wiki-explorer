#!/bin/zsh
# Build, sign, notarize and package Wiki Explorer for distribution to any Mac: a zip and a
# drag-to-Applications disk image (dist/), both notarized and stapled, plus SHA256SUMS.
#
# Required environment:
#   WIKI_EXPLORER_SIGN_IDENTITY  Developer ID Application identity, by SHA-1
#                                (list: security find-identity -v -p codesigning)
#   NOTARY_PROFILE               notarytool keychain profile (xcrun notarytool store-credentials …)
#
# Usage: WIKI_EXPLORER_SIGN_IDENTITY=… NOTARY_PROFILE=… scripts/package.sh
# VERSION and BUILD come from scripts/build-app.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

VERSION="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' scripts/build-app.sh)"
BUILD="$(sed -n 's/^BUILD="\(.*\)"$/\1/p' scripts/build-app.sh)"
APP="$ROOT/build/WikiExplorer.app"
DIST="$ROOT/dist"
ZIP="$DIST/WikiExplorer-$VERSION.zip"
DMG="$DIST/WikiExplorer-$VERSION.dmg"
SUMS="$DIST/SHA256SUMS"

[[ -n "$VERSION" && -n "$BUILD" ]] || { echo "error: could not read VERSION / BUILD from scripts/build-app.sh" >&2; exit 1; }
[[ -n "${WIKI_EXPLORER_SIGN_IDENTITY:-}" ]] || { echo "error: WIKI_EXPLORER_SIGN_IDENTITY is not set (Developer ID Application SHA-1)" >&2; exit 1; }
[[ -n "${NOTARY_PROFILE:-}" ]] || { echo "error: NOTARY_PROFILE is not set (distribution builds must be notarized)" >&2; exit 1; }

echo "=== Packaging Wiki Explorer $VERSION (build $BUILD) ==="

# 1. Tests: never package from a red tree.
swift test

# 2. Build + sign (universal, Developer ID, hardened runtime).
scripts/build-app.sh

# 3. The signature must be Developer ID with the hardened runtime, and the binary universal.
codesign --verify --deep --strict --verbose=2 "$APP"
SIGNATURE="$(codesign -dvv "$APP" 2>&1)"
[[ "$SIGNATURE" == *"Authority=Developer ID Application"* ]] || { echo "error: not signed with a Developer ID Application identity" >&2; exit 1; }
[[ "$SIGNATURE" =~ "flags=0x[0-9a-f]+\(runtime\)" ]] || { echo "error: hardened runtime is not enabled" >&2; exit 1; }
[[ "$(lipo -archs "$APP/Contents/MacOS/WikiExplorer")" == *"x86_64"*"arm64"* || "$(lipo -archs "$APP/Contents/MacOS/WikiExplorer")" == *"arm64"*"x86_64"* ]] || { echo "error: the binary is not universal" >&2; exit 1; }

# 4. Zip, notarize, staple, zip again (ditto is the format Apple recommends).
mkdir -p "$DIST"
make_zip() { rm -f "$ZIP"; ditto -c -k --norsrc --keepParent "$APP" "$ZIP"; }
make_zip
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
make_zip
spctl --assess --type execute --verbose=2 "$APP"

# 5. Disk image with the install notes, signed, notarized and stapled.
STAGE="$ROOT/build/dmg-root"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Wiki Explorer.app"
ln -s /Applications "$STAGE/Applications"
cp packaging/macos/INSTALL.txt "$STAGE/INSTALL.txt"
hdiutil create -volname "Wiki Explorer $VERSION" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"
codesign --force --timestamp --sign "$WIKI_EXPLORER_SIGN_IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

# 6. Checksums.
(cd "$DIST" && shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" > "$SUMS")

echo ""
echo "=== Package complete ==="
echo "Version: $VERSION (build $BUILD)"
echo "Zip:     $ZIP"
echo "DMG:     $DMG"
cat "$SUMS"
