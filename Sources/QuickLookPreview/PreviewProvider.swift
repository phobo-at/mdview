import MarkdownViewerCore
import QuickLookUI
import UniformTypeIdentifiers

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let html = try MarkdownPage.html(contentsOf: request.fileURL)
        return QLPreviewReply(
            dataOfContentType: .html,
            contentSize: CGSize(width: 800, height: 800)
        ) { _ in
            Data(html.utf8)
        }
    }
}
