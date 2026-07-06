import SwiftUI
import AppKit

/// A plain-text editor over `NSTextView`, used by the document window's edit
/// mode to show and edit the raw Markdown (frontmatter included).
///
/// SwiftUI's `TextEditor` can't be used here: on macOS it applies the system
/// smart-substitution rules, which silently rewrite the *source* — `"` becomes
/// a curly quote, `--` becomes an em dash — and would corrupt the Markdown/HTML
/// the user is editing. This bridge turns every substitution off so what you
/// type is exactly what gets saved.
struct RawTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.string = text

        // Editing, not display.
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)

        // Keep the source verbatim — no smart quotes/dashes/replacements/autocorrect
        // rewriting what the user types (see the type doc above).
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        // Entering edit mode should be immediately typeable — focus the editor
        // once it's in a window (not yet attached during makeNSView).
        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // Keep the coordinator's binding current so write-back always targets
        // this view's document, even if SwiftUI hands us a fresh binding.
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Only overwrite when the model diverges (e.g. a revert), so ordinary
        // typing doesn't reset the insertion point/selection on every keystroke.
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RawTextEditor

        init(_ parent: RawTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
