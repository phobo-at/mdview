import SwiftUI
import MarkdownViewerCore

@main
struct MarkdownViewerApp: App {
    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { configuration in
            WebView(html: MarkdownPage.html(from: configuration.document.text))
                .frame(minWidth: 400, minHeight: 300)
        }
        Settings {
            SettingsView()
        }
    }
}
