import SwiftUI
import UniformTypeIdentifiers

enum DefaultHandler {
    static var isDefault: Bool {
        NSWorkspace.shared.urlForApplication(toOpen: MarkdownDocument.markdownType)?.standardizedFileURL
            == Bundle.main.bundleURL.standardizedFileURL
    }

    static func makeDefault(completion: @escaping (Error?) -> Void) {
        NSWorkspace.shared.setDefaultApplication(
            at: Bundle.main.bundleURL,
            toOpen: MarkdownDocument.markdownType
        ) { error in
            DispatchQueue.main.async { completion(error) }
        }
    }
}

struct SettingsView: View {
    @State private var isDefault = DefaultHandler.isDefault
    @State private var errorMessage: String?
    @AppStorage(DefaultsKey.loadRemoteImages) private var loadRemoteImages = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                if isDefault {
                    Label("Markdown Viewer is the default app for Markdown files.",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("Markdown files (.md) currently open with another app.")
                    Button("Use Markdown Viewer for Markdown Files") {
                        errorMessage = nil
                        DefaultHandler.makeDefault { error in
                            if let error {
                                errorMessage = error.localizedDescription
                            }
                            isDefault = DefaultHandler.isDefault
                        }
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Load remote images", isOn: $loadRemoteImages)
                Text("Off by default. Remote images can reveal your IP address and be used to track when you open a document.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear { isDefault = DefaultHandler.isDefault }
    }
}
