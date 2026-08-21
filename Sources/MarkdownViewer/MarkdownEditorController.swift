import SwiftUI
import AppKit
import MarkdownViewerCore

/// Bridges the edit-mode formatting toolbar / Format menu to the raw editor's
/// `NSTextView`. Holds a weak reference to the text view (set by `RawTextEditor`)
/// and applies a `MarkdownEditor` transformation to the current selection.
///
/// Edits go through `shouldChangeText` / `textStorage` / `didChangeText`, so native
/// undo (⌘Z), the unsaved-changes dot, ⌘S/autosave and the delegate's write-back
/// to `document.text` all keep working — the toolbar only mutates the text buffer,
/// never the locked-down rendering surface (JS off, CSP; see the Security model).
final class MarkdownEditorController: ObservableObject {
    weak var textView: NSTextView?

    func apply(_ format: MarkdownFormat) {
        guard let textView else { return }
        apply(MarkdownEditor.edit(format, in: textView.string, selection: textView.selectedRange()))
        // A toolbar-button click moves first responder off the editor; put it back
        // so the user can keep typing where the edit landed.
        textView.window?.makeFirstResponder(textView)
    }

    /// Apply one range replacement to the text view. Shared by the formatting
    /// actions and by find & replace (`FindController`), so both get the same
    /// undo grouping and document write-back.
    ///
    /// Returns whether the edit was applied — the caller must not reposition the
    /// selection itself if it wasn't, because `edit.selection` is computed against
    /// the post-replacement text and would point past the end of the string.
    @discardableResult
    func apply(_ edit: MarkdownEdit) -> Bool {
        guard let textView,
              textView.shouldChangeText(in: edit.range, replacementString: edit.replacement)
        else { return false }

        textView.textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        textView.didChangeText()          // fires textDidChange → write-back to document.text
        textView.setSelectedRange(edit.selection)
        textView.scrollRangeToVisible(edit.selection)
        return true
    }
}

/// Lets the Format menu reach the frontmost document's editor. Published only while
/// editing (see `DocumentView`), so the menu's items disable themselves in preview.
struct MarkdownEditorKey: FocusedValueKey {
    typealias Value = MarkdownEditorController
}

extension FocusedValues {
    var markdownEditor: MarkdownEditorController? {
        get { self[MarkdownEditorKey.self] }
        set { self[MarkdownEditorKey.self] = newValue }
    }
}
