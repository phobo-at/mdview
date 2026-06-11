#!/bin/zsh
# Builds MarkdownViewer.app into ./dist
set -euo pipefail
cd "$(dirname "$0")"

# Use the full Xcode toolchain (SwiftUI/WebKit need it)
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

swift build -c release

if [[ ! -f Resources/AppIcon.icns ]]; then
    swift tools/make-icon.swift /tmp/mdview-AppIcon.iconset
    iconutil -c icns /tmp/mdview-AppIcon.iconset -o Resources/AppIcon.icns
fi

APP=dist/MarkdownViewer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MarkdownViewer "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# Quick Look preview extension (space bar in Finder); must be signed
# sandboxed and before the enclosing app
APPEX="$APP/Contents/PlugIns/QuickLookPreview.appex"
mkdir -p "$APPEX/Contents/MacOS"
cp .build/release/QuickLookPreview "$APPEX/Contents/MacOS/"
cp Resources/QuickLookPreview-Info.plist "$APPEX/Contents/Info.plist"
codesign --force --sign - --entitlements Resources/QuickLookPreview.entitlements "$APPEX"

codesign --force --sign - "$APP"

# Register with Launch Services so Finder knows it opens .md files
# (also registers the Quick Look extension with PlugInKit)
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$PWD/$APP"

echo "Built $APP"
