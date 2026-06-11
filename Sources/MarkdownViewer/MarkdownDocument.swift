import SwiftUI
import UniformTypeIdentifiers

struct MarkdownDocument: FileDocument {
    static let markdownType = UTType(importedAs: "net.daringfireball.markdown")

    static var readableContentTypes: [UTType] { [markdownType, .plainText] }
    static var writableContentTypes: [UTType] { [] }

    var text: String

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.fileWriteNoPermission)
    }
}
