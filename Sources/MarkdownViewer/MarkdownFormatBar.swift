import SwiftUI
import MarkdownViewerCore

/// The Markdown formatting toolbar shown above the raw editor in edit mode. Each
/// button asks the `MarkdownEditorController` to apply a `MarkdownFormat` to the
/// current selection. Grouped by kind, scrollable when the window is narrow.
struct MarkdownFormatBar: View {
    let editor: MarkdownEditorController

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                heading(1)
                heading(2)
                heading(3)

                separator

                button(.bold, "bold", "Bold", "⌘B")
                button(.italic, "italic", "Italic", "⌘I")
                button(.strikethrough, "strikethrough", "Strikethrough", "⇧⌘X")
                button(.inlineCode, "chevron.left.forwardslash.chevron.right", "Inline code", "⌥⌘C")

                separator

                button(.bulletList, "list.bullet", "Bulleted list")
                button(.numberedList, "list.number", "Numbered list")
                button(.quote, "text.quote", "Block quote")

                separator

                button(.link, "link", "Link", "⌘K")
                button(.codeBlock, "curlybraces", "Code block")
                button(.horizontalRule, "minus", "Horizontal rule")
                button(.table, "tablecells", "Table")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .background(.bar)
    }

    // A symbol button that applies a format.
    private func button(_ format: MarkdownFormat, _ symbol: String, _ title: String, _ shortcut: String? = nil) -> some View {
        Button {
            editor.apply(format)
        } label: {
            Image(systemName: symbol)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(shortcut.map { "\(title) (\($0))" } ?? title)
    }

    // Headings have no clean per-level SF Symbol, so use a compact "H1/H2/H3" label.
    private func heading(_ level: Int) -> some View {
        Button {
            editor.apply(.heading(level))
        } label: {
            Text("H\(level)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Heading \(level) (⌃⌘\(level))")
    }

    private var separator: some View {
        Divider().frame(height: 16).padding(.horizontal, 2)
    }
}
