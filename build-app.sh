#!/bin/zsh
# Builds MarkdownViewer.app into ./dist
set -euo pipefail
cd "$(dirname "$0")"

# Use the full Xcode toolchain (SwiftUI/WebKit need it)
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# Signing / notarization — auto-detected so the build works on any machine:
#   • Developer ID identity present in the keychain → full release flow
#     (Developer ID + hardened runtime + secure timestamp, then notarize +
#     staple unless NOTARIZE=0). This is what produces the distributable.
#   • Identity missing → automatic ad-hoc fallback: the app runs on THIS Mac
#     but Gatekeeper flags it elsewhere, so it's for local use, not release.
# Overrides: SIGN_IDENTITY (a cert name, or "-" to force ad-hoc), NOTARY_PROFILE,
# TEAM_ID, NOTARIZE=0 (skip the Apple round-trip, keep Developer ID signing).
IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Soon Up GmbH (6A2SZH3VT5)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-ainstype-notary}"
NOTARIZE="${NOTARIZE:-1}"

# Resolve the signing mode: honour an explicit "-", else use the Developer ID
# identity if the keychain has it, else warn and fall back to ad-hoc.
if [[ "$IDENTITY" == "-" ]]; then
    ADHOC=1
elif security find-identity -v -p codesigning 2>/dev/null | grep -qF -- "$IDENTITY"; then
    ADHOC=0
else
    echo "⚠️  Signing identity not found in keychain:"
    echo "      $IDENTITY"
    echo "    → Falling back to ad-hoc signing (runs on this Mac, NOT distributable)."
    echo "      Install the Developer ID cert (or set SIGN_IDENTITY) for a release build."
    IDENTITY="-"
    ADHOC=1
fi

# Ad-hoc signatures can carry neither an Apple secure timestamp nor a notary
# ticket, so drop --timestamp and force-skip notarization in that mode.
if [[ "$ADHOC" == "1" ]]; then
    NOTARIZE=0
    TIMESTAMP=()
else
    TIMESTAMP=(--timestamp)
fi

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

# Sign inside-out with hardened runtime (+ secure timestamp for a real identity,
# which notarization requires). Sign the nested appex first, then the enclosing
# app; no --deep so the appex signature is left intact.
codesign --force --options runtime "${TIMESTAMP[@]}" \
    --entitlements Resources/QuickLookPreview.entitlements \
    --sign "$IDENTITY" "$APPEX"

codesign --force --options runtime "${TIMESTAMP[@]}" \
    --sign "$IDENTITY" "$APP"

codesign --verify --deep --strict "$APP"
if [[ "$ADHOC" == "1" ]]; then
    echo "Signature OK (ad-hoc — local use only)"
else
    echo "Signature OK ($IDENTITY)"
fi

# Package: always produce dist/MarkdownViewer.zip as the hand-off artifact
# (ditto --keepParent preserves the bundle + signature). With a Developer ID
# identity we then notarize + staple so Gatekeeper passes with no prompt on any
# Mac; an ad-hoc / non-notarized zip still runs, just with a one-time first-open.
ZIP=dist/MarkdownViewer.zip
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

if [[ "$NOTARIZE" == "1" ]]; then
    echo "Submitting to Apple notary service (this can take a few minutes)…"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"

    # Re-zip the stapled app as the distributable artifact.
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Notarized + stapled. Distributable: $ZIP"
elif [[ "$ADHOC" == "1" ]]; then
    echo "Ad-hoc signed → $ZIP. Recipients open it once via right-click → Open"
    echo "(if macOS says \"damaged\", they run: xattr -dr com.apple.quarantine <app>)."
else
    echo "Developer ID signed, not notarized (NOTARIZE=0). Artifact: $ZIP"
fi

# Register with Launch Services so Finder knows it opens .md files
# (also registers the Quick Look extension with PlugInKit)
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$PWD/$APP"

echo "Built $APP"
