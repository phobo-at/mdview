import SwiftUI
import MarkdownViewerCore

@main
struct MarkdownViewerApp: App {
    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { configuration in
            DocumentView(
                text: configuration.document.text,
                fileURL: configuration.fileURL
            )
        }
        // Open documents in a comfortable portrait reading window.
        .defaultSize(width: 820, height: 1040)
        .commands {
            DocumentCommands()
        }
        Settings {
            SettingsView()
        }
    }
}

/// Renders one Markdown document and exposes its web view to the menu bar.
struct DocumentView: View {
    let text: String
    let fileURL: URL?
    @StateObject private var holder = WebViewHolder()

    var body: some View {
        let html = MarkdownPage.html(from: text)
        WebView(html: html, holder: holder)
            .frame(minWidth: 480, minHeight: 600)
            .focusedSceneValue(\.webViewHolder, holder)
            .onAppear {
                holder.html = html
                if let name = fileURL?.deletingPathExtension().lastPathComponent {
                    holder.documentName = name
                }
            }
    }
}

/// Print and "Save as PDF" entries in the File menu, acting on the frontmost
/// document window.
struct DocumentCommands: Commands {
    @FocusedValue(\.webViewHolder) private var holder

    var body: some Commands {
        CommandGroup(replacing: .printItem) {
            Button("Print…") { holder?.print() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(holder?.hasContent != true)

            Button("Save as PDF…") { holder?.exportPDF() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(holder?.hasContent != true)
        }
    }
}
