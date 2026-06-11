# Markdown Viewer

Minimal native macOS app (SwiftUI, SPM — no Xcode project) that opens `.md` files on double-click and renders them GitHub-style in a `WKWebView`.

## Toolchain

`xcode-select` on this machine points to the Command Line Tools, which cannot build SwiftUI or run tests. Every `swift` command needs the full Xcode toolchain:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

`build-app.sh` sets this itself.

## Commands

```sh
./build-app.sh        # build dist/MarkdownViewer.app, sign ad-hoc, register with Launch Services
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test   # run core tests (Swift Testing, not XCTest)
```

## Architecture

- `Sources/MarkdownViewerCore/MarkdownPage.swift` — the only real logic: markdown → complete styled HTML page (Ink parser + embedded CSS with light/dark support). Covered by tests in `Tests/`; changes here are developed test-first.
- `Sources/MarkdownViewer/` — UI shell: `DocumentGroup` viewer app, read-only `FileDocument`, `WKWebView` wrapper (links open in the default browser).
- `Sources/QuickLookPreview/` — Quick Look preview extension (space bar in Finder): a data-based `QLPreviewProvider` returning `MarkdownPage` HTML, which Quick Look renders itself — no web view in the extension. Entry point is `NSExtensionMain` via linker flags in `Package.swift`; `main.swift` is a required-but-unused stub. `build-app.sh` assembles `Contents/PlugIns/QuickLookPreview.appex` from the binary plus `Resources/QuickLookPreview-Info.plist` and signs it with `Resources/QuickLookPreview.entitlements` (app extensions must be sandboxed; sign the appex before the app). Debug: `pluginkit -m -p com.apple.quicklook.preview` shows registration, `qlmanage -p file.md` previews, `qlmanage -r` resets caches. (`qlmanage -p -o dir` crashes inside ExtensionFoundation on this macOS — not an appex bug.)
- `Resources/Info.plist` — declares the `net.daringfireball.markdown` document type (`md`, `markdown`, `mdown`, `mkdn`, `mkd`); this is what makes Finder offer the app for double-click.
- `tools/make-icon.swift` — the app icon is code, not an asset: draws a white squircle with black monospace ".md" at all iconset sizes; `build-app.sh` compiles it to `Resources/AppIcon.icns` if missing. Delete the `.icns` to force regeneration after changing the drawing.

## Default handler for .md

Declaring the document type only makes the app *an option* in "Open with". Making it the *default* is a per-user Launch Services setting. The app's Settings window (⌘,) has a button for this (`SettingsView.swift` — uses `NSWorkspace.setDefaultApplication` on `Bundle.main.bundleURL`, so it works from any install location). It can also be set from the CLI:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift -e '
import AppKit
import UniformTypeIdentifiers
let url = URL(fileURLWithPath: "/Applications/MarkdownViewer.app")  // adjust path
let sem = DispatchSemaphore(value: 0)
NSWorkspace.shared.setDefaultApplication(at: url, toOpen: UTType(importedAs: "net.daringfireball.markdown")) { error in
    print(error.map { "ERROR: \($0)" } ?? "default handler set"); sem.signal()
}
sem.wait()'
```

The setting points at a concrete bundle path — re-run it if the app moves (e.g. from `dist/` to `/Applications`).
