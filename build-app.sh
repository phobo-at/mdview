#!/bin/zsh
# Builds MarkdownViewer.app into ./dist
set -euo pipefail
cd "$(dirname "$0")"

# Use the full Xcode toolchain (SwiftUI/WebKit need it)
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# Signing / notarization. Override SIGN_IDENTITY when building from a fork.
# NOTARIZE=0 skips the Apple round-trip for fast local iteration (still
# Developer ID signed, just not notarized/stapled — fine on this machine).
IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Soon Up GmbH (6A2SZH3VT5)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-ainstype-notary}"
NOTARIZE="${NOTARIZE:-1}"

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

# Sign inside-out with Developer ID + hardened runtime + secure timestamp
# (all three required for notarization). Sign the nested appex first, then
# the enclosing app; no --deep so the appex signature is left intact.
codesign --force --options runtime --timestamp \
    --entitlements Resources/QuickLookPreview.entitlements \
    --sign "$IDENTITY" "$APPEX"

codesign --force --options runtime --timestamp \
    --sign "$IDENTITY" "$APP"

codesign --verify --deep --strict "$APP"
echo "Signature OK ($IDENTITY)"

# Notarize: zip the bundle, submit to Apple, then staple the ticket onto the
# .app so Gatekeeper passes even offline / on first launch on other Macs.
if [[ "$NOTARIZE" == "1" ]]; then
    ZIP=dist/MarkdownViewer.zip
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"

    echo "Submitting to Apple notary service (this can take a few minutes)…"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"

    # Re-zip the stapled app as the distributable artifact.
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Notarized + stapled. Distributable: $ZIP"
else
    echo "Skipped notarization (NOTARIZE=0). App is Developer ID signed only."
fi

# Register with Launch Services so Finder knows it opens .md files
# (also registers the Quick Look extension with PlugInKit)
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$PWD/$APP"

echo "Built $APP"
