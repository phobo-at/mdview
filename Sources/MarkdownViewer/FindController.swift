import SwiftUI
import AppKit
import WebKit
import MarkdownViewerCore

/// Find — and, while editing, find & replace — for one document window.
///
/// One bar, two surfaces:
///
/// - **Editing** searches the raw Markdown source through the pure `TextSearch`
///   core, so it can count matches ("3 of 12"), step through them and replace.
/// - **Previewing** drives `WKWebView`'s native find-in-page. That is WebKit's own
///   text search, not injected script, so it needs no JavaScript and leaves the
///   locked-down rendering surface (JS off, CSP — see the Security model) exactly
///   as it is. WebKit only reports *whether* it found a match, so the preview has
///   no counter, and replacing there would have nowhere to write to: Replace is
///   offered in edit mode only.
final class FindController: ObservableObject {

    /// Which surface the search runs against.
    enum Target { case preview, editor }

    /// Set explicitly by `DocumentView` when the view/edit toggle flips. The
    /// unmounted web view's weak reference lingers, so "is a web view still
    /// attached?" is not a reliable proxy for the current mode.
    @Published private(set) var target: Target = .preview

    /// The two surfaces, wired once by `DocumentView`. Weak: the view owns both.
    weak var editor: MarkdownEditorController?
    weak var holder: WebViewHolder?

    @Published var isPresented = false
    /// Whether the user asked for the replace row. Kept apart from `showsReplace`
    /// so toggling to the preview (where replacing is impossible) only *hides* the
    /// row — coming back to the editor brings it out again.
    private var wantsReplace = false
    @Published private(set) var showsReplace = false
    @Published var query = ""
    @Published var replacement = ""
    @Published var caseSensitive = false

    /// Short status shown in the bar: "3 of 12", "Not found", "Replaced 4", or empty.
    @Published private(set) var status = ""

    /// Bumped whenever ⌘F is pressed, so the bar moves the keyboard into the
    /// search field even when it is already open.
    @Published private(set) var focusRequest = 0

    /// Where incremental search (typing in the field) measures from, so the match
    /// doesn't run away down the document with every keystroke. Updated whenever
    /// the user explicitly steps to a match.
    private var anchor = 0

    var canReplace: Bool { target == .editor }

    // MARK: - Opening / closing

    func open(replace: Bool) {
        if !isPresented {
            isPresented = true
            wantsReplace = replace
            anchor = editorSelection()?.location ?? 0
            if let seed = selectionSeed() { query = seed }
        } else if replace {
            // ⌘F on an open bar only re-focuses the field; ⌥⌘F adds the replace
            // row to it (and never takes it away again).
            wantsReplace = true
        }
        showsReplace = wantsReplace && canReplace
        focusRequest += 1
        runIncremental()
    }

    func close() {
        isPresented = false
        wantsReplace = false
        showsReplace = false
        status = ""
        // Hand the keyboard back to the content the user was reading/editing.
        let content: NSView? = target == .editor ? editor?.textView : holder?.webView
        content?.window?.makeFirstResponder(content)
    }

    /// Follow the view/edit toggle. The two surfaces search independently, so the
    /// counter is cleared and the next explicit step re-runs against the new one.
    func retarget(_ newTarget: Target) {
        guard newTarget != target else { return }
        target = newTarget
        // Hide the replace row in the preview, and bring it back on the way in.
        showsReplace = wantsReplace && canReplace
        status = ""
        anchor = editorSelection()?.location ?? 0
    }

    /// Pre-fill the field from a short, single-line selection when the bar opens —
    /// "search for what I have selected" without needing a separate command (⌘E,
    /// the usual shortcut for that, belongs to Edit Markdown in this app).
    private func selectionSeed() -> String? {
        guard target == .editor,
              let textView = editor?.textView,
              let selection = editorSelection(), selection.length > 0, selection.length <= 200
        else { return nil }
        let selected = (textView.string as NSString).substring(with: selection)
        return selected.contains("\n") ? nil : selected
    }

    // MARK: - Finding

    func findNext() { step(forward: true) }
    func findPrevious() { step(forward: false) }

    /// Re-run the search from the anchor. Called while typing in the field and
    /// when the case toggle flips.
    func runIncremental() {
        guard !query.isEmpty else { status = ""; return }
        switch target {
        case .editor:
            let matches = editorMatches()
            move(to: TextSearch.index(after: NSRange(location: anchor, length: 0), in: matches),
                 in: matches)
        case .preview:
            findInPage(backwards: false)
        }
    }

    private func step(forward: Bool) {
        // Deliberately not gated on `isPresented`: ⌘G / ⇧⌘G conventionally continue
        // the last search after the bar has been closed, and `query` survives `close()`.
        guard !query.isEmpty else { return }
        switch target {
        case .editor:
            let matches = editorMatches()
            let selection = editorSelection() ?? NSRange(location: anchor, length: 0)
            let index = forward
                ? TextSearch.index(after: selection, in: matches)
                : TextSearch.index(before: selection, in: matches)
            move(to: index, in: matches)
        case .preview:
            findInPage(backwards: !forward)
        }
    }

    private func editorMatches() -> [NSRange] {
        guard let textView = editor?.textView else { return [] }
        return TextSearch.matches(of: query, in: textView.string, caseSensitive: caseSensitive)
    }

    private func editorSelection() -> NSRange? {
        target == .editor ? editor?.textView?.selectedRange() : nil
    }

    /// Select the match at `index`, scroll it into view and update the counter.
    private func move(to index: Int?, in matches: [NSRange]) {
        guard let index, let textView = editor?.textView else {
            status = query.isEmpty ? "" : "Not found"
            return
        }
        let match = matches[index]
        textView.setSelectedRange(match)
        textView.scrollRangeToVisible(match)
        // The find bar holds first responder while typing, so the selection draws
        // in the muted secondary colour — the find indicator makes it obvious.
        textView.showFindIndicator(for: match)
        anchor = match.location
        status = "\(index + 1) of \(matches.count)"
    }

    /// WebKit's own find-in-page for the rendered preview (no JavaScript involved).
    private func findInPage(backwards: Bool) {
        guard let webView = holder?.webView, !query.isEmpty else { return }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = caseSensitive
        configuration.wraps = true
        webView.find(query, configuration: configuration) { [weak self] result in
            // WKFindResult reports only match/no match, hence no counter here.
            let found = result.matchFound
            DispatchQueue.main.async { self?.status = found ? "" : "Not found" }
        }
    }

    // MARK: - Replacing

    /// Replace the highlighted match, then move to the next one. If the selection
    /// isn't sitting on a match, this only steps — so Replace never rewrites text
    /// at an arbitrary cursor position.
    func replaceCurrent() {
        guard canReplace, !query.isEmpty,
              let editor, let textView = editor.textView else { return }

        let matches = TextSearch.matches(of: query, in: textView.string, caseSensitive: caseSensitive)
        guard let index = TextSearch.index(of: textView.selectedRange(), in: matches) else {
            step(forward: true)
            return
        }
        editor.apply(TextSearch.replacement(of: matches[index], with: replacement))
        step(forward: true)
    }

    func replaceAll() {
        guard canReplace, !query.isEmpty,
              let editor, let textView = editor.textView else { return }

        let count = TextSearch.matches(of: query, in: textView.string, caseSensitive: caseSensitive).count
        guard let edit = TextSearch.replaceAll(of: query, with: replacement,
                                               in: textView.string, caseSensitive: caseSensitive) else {
            status = "Not found"
            return
        }
        // A refused edit is not the same as "nothing matched" — say which happened.
        guard editor.apply(edit) else {
            status = "Could not replace"
            return
        }
        anchor = edit.selection.location
        status = count == 1 ? "Replaced 1" : "Replaced \(count)"
    }
}

/// Lets the Edit ▸ Find commands reach the frontmost document's find bar. Published
/// in both modes — searching works in the preview and in the editor.
struct FindControllerKey: FocusedValueKey {
    typealias Value = FindController
}

extension FocusedValues {
    var findController: FindController? {
        get { self[FindControllerKey.self] }
        set { self[FindControllerKey.self] = newValue }
    }
}
