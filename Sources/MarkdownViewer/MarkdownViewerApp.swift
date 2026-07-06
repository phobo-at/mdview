import SwiftUI
import MarkdownViewerCore

@main
struct MarkdownViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Editable document scene: opens .md files for reading and, via the
        // edit toggle, for editing/saving back to disk.
        DocumentGroup(newDocument: MarkdownDocument()) { configuration in
            DocumentView(
                document: configuration.$document,
                fileURL: configuration.fileURL
            )
        }
        // Open documents in a comfortable portrait reading window.
        .defaultSize(width: 820, height: 1040)
        .commands {
            DocumentCommands()
            FormatCommands()
        }
        Settings {
            SettingsView()
        }
    }
}

/// Renders one Markdown document and exposes its web view + edit toggle to the
/// menu bar. Starts in the rendered preview; the toolbar/⌘E toggle swaps in a
/// raw-source editor bound to the document.
struct DocumentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?
    @AppStorage(DefaultsKey.loadRemoteImages) private var loadRemoteImages = false
    @StateObject private var holder = WebViewHolder()
    @StateObject private var editor = MarkdownEditorController()
    @State private var isEditing = false

    var body: some View {
        Group {
            if isEditing {
                VStack(spacing: 0) {
                    MarkdownFormatBar(editor: editor)
                    Divider()
                    RawTextEditor(text: $document.text, controller: editor)
                }
            } else {
                PreviewView(
                    text: document.text,
                    loadRemoteImages: loadRemoteImages,
                    fileURL: fileURL,
                    holder: holder
                )
            }
        }
        .frame(minWidth: 480, minHeight: 600)
        // Expose the web view (Print/PDF/Zoom act on it) and the edit toggle
        // (View ▸ Edit Markdown) to the menu bar for the frontmost window. The
        // holder is published only while previewing, so those preview-only
        // commands disable themselves automatically during editing.
        .focusedSceneValue(\.webViewHolder, isEditing ? nil : holder)
        .focusedSceneValue(\.editToggle, $isEditing)
        // The Format menu acts on the editor, so publish it only while editing —
        // a nil value disables the whole menu in preview.
        .focusedSceneValue(\.markdownEditor, isEditing ? editor : nil)
        .toolbar {
            ToolbarItem {
                Button {
                    isEditing.toggle()
                } label: {
                    Label(isEditing ? "Done" : "Edit",
                          systemImage: isEditing ? "eye" : "pencil")
                }
                .help(isEditing ? "Show the rendered preview" : "Edit the Markdown source")
            }
        }
    }
}

/// The rendered, read-only preview: Markdown → styled HTML in the locked-down
/// web view. Only mounted while not editing, so the web view (and thus the
/// Print/PDF/Zoom commands) is torn down during editing.
private struct PreviewView: View {
    let text: String
    let loadRemoteImages: Bool
    let fileURL: URL?
    let holder: WebViewHolder

    var body: some View {
        let html = MarkdownPage.html(from: text, allowRemoteImages: loadRemoteImages)
        WebView(html: html, holder: holder)
            // Browser-style un-shifted ⌘= as an alias for Zoom In. The visible
            // View-menu item advertises the HIG-conventional ⌘+ (i.e. ⌘⇧=);
            // this hidden button adds ⌘= without a duplicate menu entry.
            .background {
                Button("Zoom In", action: holder.zoomIn)
                    .keyboardShortcut("=", modifiers: .command)
                    .hidden()
            }
            .onAppear {
                holder.html = html
                if let name = fileURL?.deletingPathExtension().lastPathComponent {
                    holder.documentName = name
                }
            }
            // Keep the export HTML in sync when the text or the image setting
            // changes while a document is open.
            .onChange(of: html) { holder.html = $0 }
    }
}

/// File-menu Print / "Save as PDF" and View-menu Edit / Zoom entries, all acting
/// on the frontmost document window via focused scene values.
struct DocumentCommands: Commands {
    @FocusedValue(\.webViewHolder) private var holder
    @FocusedValue(\.editToggle) private var editToggle

    /// Print/PDF/Zoom need a rendered preview. `DocumentView` publishes the
    /// holder only while previewing, so a nil holder already means "editing, or
    /// no document" — no separate edit flag needed.
    private var previewUnavailable: Bool { holder?.hasContent != true }

    var body: some Commands {
        CommandGroup(replacing: .printItem) {
            Button("Print…") { holder?.print() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(previewUnavailable)

            Button("Save as PDF…") { holder?.exportPDF() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(previewUnavailable)
        }

        // Edit toggle + Zoom land in the View menu (after the system's toolbar
        // items). Edit is enabled whenever a document window is frontmost; Zoom
        // acts on the preview, so it's disabled while editing.
        CommandGroup(after: .toolbar) {
            Button(editToggle?.wrappedValue == true ? "Stop Editing" : "Edit Markdown") {
                editToggle?.wrappedValue.toggle()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(editToggle == nil)

            Divider()

            Button("Zoom In") { holder?.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(previewUnavailable)

            Button("Zoom Out") { holder?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(previewUnavailable)

            Button("Actual Size") { holder?.resetZoom() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(previewUnavailable)

            Divider()
        }
    }
}

/// A "Format" menu mirroring the edit-mode toolbar, with keyboard shortcuts for the
/// common actions. Acts on the frontmost document's editor via `markdownEditor`,
/// which `DocumentView` publishes only while editing — so every item disables
/// itself in the rendered preview.
struct FormatCommands: Commands {
    @FocusedValue(\.markdownEditor) private var editor

    var body: some Commands {
        CommandMenu("Format") {
            item("Heading 1", .heading(1), "1", [.control, .command])
            item("Heading 2", .heading(2), "2", [.control, .command])
            item("Heading 3", .heading(3), "3", [.control, .command])

            Divider()

            item("Bold", .bold, "b", .command)
            item("Italic", .italic, "i", .command)
            item("Strikethrough", .strikethrough, "x", [.shift, .command])
            item("Inline Code", .inlineCode, "c", [.option, .command])

            Divider()

            item("Bulleted List", .bulletList)
            item("Numbered List", .numberedList)
            item("Block Quote", .quote)

            Divider()

            item("Link…", .link, "k", .command)
            item("Code Block", .codeBlock)
            item("Horizontal Rule", .horizontalRule)
            item("Table", .table)
        }
    }

    @ViewBuilder
    private func item(_ title: String, _ format: MarkdownFormat,
                      _ key: KeyEquivalent? = nil,
                      _ modifiers: EventModifiers = .command) -> some View {
        let button = Button(title) { editor?.apply(format) }.disabled(editor == nil)
        if let key {
            button.keyboardShortcut(key, modifiers: modifiers)
        } else {
            button
        }
    }
}
