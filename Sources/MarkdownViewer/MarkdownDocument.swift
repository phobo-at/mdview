import SwiftUI
import UniformTypeIdentifiers

struct MarkdownDocument: FileDocument {
    static let markdownType = UTType(importedAs: "net.daringfireball.markdown")

    static var readableContentTypes: [UTType] { [markdownType, .plainText] }
    // Writable so the in-app edit mode can save changes back to disk. Saving
    // only ever writes plain UTF-8 text the user typed — it does not touch the
    // locked-down rendering surface (see WebView / MarkdownPage). Mirrors
    // `readableContentTypes` so a file opened as plain text (not just as the
    // markdown UTI) can also be saved; the byte output is identical either way.
    static var writableContentTypes: [UTType] { [markdownType, .plainText] }

    var text: String

    /// Empty document, used by the editable `DocumentGroup` initializer for
    /// File ▸ New and when the app is launched without a file.
    init() {
        text = ""
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
