#!/bin/zsh
# Build WikiExplorer.app (release, universal: Apple silicon + Intel) into build/ and sign it.
#
#   WIKI_EXPLORER_SIGN_IDENTITY=<Developer ID SHA-1> scripts/build-app.sh [--install]
#   scripts/build-app.sh --adhoc [--install]     # local builds only: ad-hoc signature, this Mac only
#
# A Developer ID signature (hardened runtime, secure timestamp) is what lets the app run on any Mac once
# notarized; scripts/package.sh notarizes and packages it. Two Developer ID identities share the same name,
# so pass the SHA-1 (list: security find-identity -v -p codesigning). The app needs the llm-wiki CLI
# (wiki-v2: `pnpm link:global`) on the Mac it runs on.
set -euo pipefail
cd "$(dirname "$0")/.."

ADHOC=0
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --adhoc) ADHOC=1 ;;
    --install) INSTALL=1 ;;
    *) echo "usage: scripts/build-app.sh [--adhoc] [--install]" >&2; exit 2 ;;
  esac
done
if [[ $ADHOC -eq 0 && -z "${WIKI_EXPLORER_SIGN_IDENTITY:-}" ]]; then
  echo "error: WIKI_EXPLORER_SIGN_IDENTITY is not set (Developer ID Application SHA-1), and --adhoc was not given. Identities:" >&2
  security find-identity -v -p codesigning >&2
  exit 1
fi

VERSION="0.4.0"
BUILD="5"
APP="build/WikiExplorer.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/WikiExplorer"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/WikiExplorer"
rm -rf build/AppIcon.iconset
swift scripts/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.giorgosmarinos.wiki-explorer</string>
  <key>CFBundleName</key><string>Wiki Explorer</string>
  <key>CFBundleDisplayName</key><string>Wiki Explorer</string>
  <key>CFBundleExecutable</key><string>WikiExplorer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 Giorgos Marinos</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

if [[ $ADHOC -eq 1 ]]; then
  codesign --force --sign - --identifier com.giorgosmarinos.wiki-explorer "$APP"
else
  codesign --force --options runtime --timestamp \
    --identifier com.giorgosmarinos.wiki-explorer --sign "$WIKI_EXPLORER_SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"
lipo -archs "$APP/Contents/MacOS/WikiExplorer"
echo "built $APP"

if [[ $INSTALL -eq 1 ]]; then
  pkill -x WikiExplorer 2>/dev/null || true
  rm -rf "/Applications/Wiki Explorer.app"
  cp -R "$APP" "/Applications/Wiki Explorer.app"
  open "/Applications/Wiki Explorer.app"
  echo "installed /Applications/Wiki Explorer.app"
fi
