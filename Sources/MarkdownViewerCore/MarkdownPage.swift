import Foundation
import Ink

public enum MarkdownPage {
    public static func html(contentsOf url: URL, allowRemoteImages: Bool = false) throws -> String {
        let data = try Data(contentsOf: url)
        let markdown = String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)
        return html(from: markdown, allowRemoteImages: allowRemoteImages)
    }

    public static func html(from markdown: String, allowRemoteImages: Bool = false) -> String {
        let (frontmatter, body) = splitFrontmatter(markdown)
        let bodyHTML = MarkdownParser().html(from: String(body))
        let frontmatterHTML = frontmatter.map { renderFrontmatter(String($0)) } ?? ""
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(csp(allowRemoteImages: allowRemoteImages))">
        <style>
        \(css)
        </style>
        </head>
        <body>
        <article>
        \(frontmatterHTML)
        \(bodyHTML)
        </article>
        </body>
        </html>
        """
    }

    // MARK: - YAML frontmatter

    /// Splits a leading YAML frontmatter block (`---` … `---`/`...`) off the top
    /// of the document so it can be rendered as structured metadata instead of
    /// leaking into the Markdown body. Ink's own metadata parser only handles a
    /// flat, list-free `key: value` block and silently re-renders anything richer
    /// (nested maps, sequences) as body text — so we peel the block off ourselves.
    ///
    /// Frontmatter is recognised only when the very first line (after an optional
    /// BOM) is exactly `---` and a later line is exactly `---` or `...`. If there
    /// is no closing delimiter the input is left untouched (a bare `---` on a
    /// later line stays in the body and still renders as a thematic break).
    static func splitFrontmatter(_ markdown: String) -> (frontmatter: Substring?, body: Substring) {
        var content = Substring(markdown)
        if content.first == "\u{FEFF}" { content = content.dropFirst() }

        guard let firstLineEnd = content.firstIndex(of: "\n") else {
            return (nil, Substring(markdown))
        }
        let firstLine = content[content.startIndex..<firstLineEnd]
        guard String(firstLine).trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
            return (nil, Substring(markdown))
        }

        var searchIndex = content.index(after: firstLineEnd)
        let frontmatterStart = searchIndex
        while searchIndex < content.endIndex {
            let lineEnd = content[searchIndex...].firstIndex(of: "\n") ?? content.endIndex
            let trimmed = String(content[searchIndex..<lineEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "---" || trimmed == "..." {
                let frontmatter = content[frontmatterStart..<searchIndex]
                let bodyStart = lineEnd < content.endIndex ? content.index(after: lineEnd) : content.endIndex
                return (frontmatter, content[bodyStart...])
            }
            if lineEnd == content.endIndex { break }
            searchIndex = content.index(after: lineEnd)
        }
        return (nil, Substring(markdown))
    }

    /// Renders a frontmatter block as a self-contained, HTML-escaped "properties
    /// card". Frontmatter is untrusted input, so every key and value is escaped
    /// (`htmlEscape`) before it enters the HTML. If the block can't be parsed
    /// cleanly it degrades to the raw YAML in a `<pre>` — never back to a run-on
    /// paragraph.
    static func renderFrontmatter(_ yaml: String) -> String {
        let trimmed = yaml.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard let node = parseFrontmatter(yaml) else {
            return "<section class=\"frontmatter\"><pre>\(htmlEscape(trimmed))</pre></section>"
        }
        return "<section class=\"frontmatter\">\(renderNode(node))</section>"
    }

    private static func renderNode(_ node: YAMLNode) -> String {
        switch node {
        case .scalar(let value):
            return renderScalar(value)
        case .sequence(let items):
            return "<ul>" + items.map { "<li>\(renderNode($0))</li>" }.joined() + "</ul>"
        case .mapping(let pairs):
            let rows = pairs.map { "<dt>\(htmlEscape($0.key))</dt><dd>\(renderNode($0.value))</dd>" }.joined()
            return "<dl>\(rows)</dl>"
        }
    }

    /// Escapes a scalar and, matching Ink's own body behaviour, turns a bare
    /// `http(s)` URL into a link (only those two schemes; the href is escaped and
    /// navigation is still intercepted by the web view and the CSP).
    private static func renderScalar(_ value: String) -> String {
        let escaped = htmlEscape(value)
        if value.hasPrefix("https://") || value.hasPrefix("http://"), !value.contains(" ") {
            return "<a href=\"\(escaped)\">\(escaped)</a>"
        }
        return escaped
    }

    private indirect enum YAMLNode {
        case scalar(String)
        case sequence([YAMLNode])
        case mapping([(key: String, value: YAMLNode)])
    }

    private struct FrontmatterLine {
        let indent: Int
        let text: String
    }

    /// Parses the indentation-based YAML subset used in real frontmatter:
    /// scalars, nested maps and block sequences. Returns `nil` if the block can't
    /// be consumed cleanly (leftover lines, unsupported construct, empty result)
    /// so the caller can fall back to showing the raw block — this guarantees we
    /// never silently drop data or regress to the collapsed-paragraph bug.
    private static func parseFrontmatter(_ yaml: String) -> YAMLNode? {
        let lines = tokenize(yaml)
        guard !lines.isEmpty else { return nil }
        var index = 0
        let node = parseBlock(lines, &index, indent: lines[0].indent)
        guard index == lines.count else { return nil }
        switch node {
        case .mapping(let pairs): return pairs.isEmpty ? nil : node
        case .sequence(let items): return items.isEmpty ? nil : node
        case .scalar: return node
        }
    }

    private static func tokenize(_ yaml: String) -> [FrontmatterLine] {
        var result: [FrontmatterLine] = []
        for rawLine in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = rawLine
            if line.last == "\r" { line = line.dropLast() }
            let body = line.drop { $0 == " " }
            let indent = line.count - body.count
            let text = String(body).trimmingCharacters(in: .whitespaces)
            if text.isEmpty || text.hasPrefix("#") { continue }
            result.append(FrontmatterLine(indent: indent, text: text))
        }
        return result
    }

    private static func parseBlock(_ lines: [FrontmatterLine], _ index: inout Int, indent: Int) -> YAMLNode {
        if index < lines.count, lines[index].indent == indent, isSequenceItem(lines[index].text) {
            var items: [YAMLNode] = []
            while index < lines.count, lines[index].indent == indent, isSequenceItem(lines[index].text) {
                let itemIndent = lines[index].indent
                let rest = sequenceItemContent(lines[index].text)
                index += 1
                if rest.isEmpty, index < lines.count, lines[index].indent > itemIndent {
                    items.append(parseBlock(lines, &index, indent: lines[index].indent))
                } else {
                    items.append(.scalar(rest))
                }
            }
            return .sequence(items)
        }

        var pairs: [(key: String, value: YAMLNode)] = []
        while index < lines.count, lines[index].indent == indent, !isSequenceItem(lines[index].text) {
            guard let pair = splitKeyValue(lines[index].text) else { break }
            index += 1
            if pair.value.isEmpty, index < lines.count, lines[index].indent > indent {
                let child = parseBlock(lines, &index, indent: lines[index].indent)
                pairs.append((pair.key, child))
            } else {
                pairs.append((pair.key, .scalar(pair.value)))
            }
        }
        return .mapping(pairs)
    }

    private static func isSequenceItem(_ text: String) -> Bool {
        text == "-" || text.hasPrefix("- ")
    }

    private static func sequenceItemContent(_ text: String) -> String {
        text == "-" ? "" : String(text.dropFirst(2))
    }

    private static func splitKeyValue(_ text: String) -> (key: String, value: String)? {
        if let range = text.range(of: ": ") {
            let key = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let value = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return (key, value)
        }
        if text.hasSuffix(":") {
            return (String(text.dropLast()).trimmingCharacters(in: .whitespaces), "")
        }
        return nil
    }

    private static func htmlEscape(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.count)
        for character in string {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
        return result
    }

    /// Locks the rendered page down: untrusted `.md` files can contain raw HTML
    /// (Ink passes it through unsanitised), so this stops any inline/remote
    /// script from running. `style-src 'unsafe-inline'` allows our own embedded
    /// `<style>`.
    ///
    /// By default `img-src data:` permits inline images only — remote images are
    /// blocked because they auto-load and leak the reader's IP / act as tracking
    /// beacons. When the user opts in (`allowRemoteImages`), remote `http`/`https`
    /// images are allowed too; scripts and every other resource type stay blocked.
    static func csp(allowRemoteImages: Bool) -> String {
        let img = allowRemoteImages ? "data: https: http:" : "data:"
        return "default-src 'none'; style-src 'unsafe-inline'; img-src \(img);"
    }

    static let css = """
    :root {
        color-scheme: light dark;
        --fg: #1f2328;
        --bg: #ffffff;
        --muted: #59636e;
        --border: #d1d9e0;
        --code-bg: #f6f8fa;
        --link: #0969da;
        --quote: #59636e;
    }
    @media (prefers-color-scheme: dark) {
        :root {
            --fg: #f0f6fc;
            --bg: #212830;
            --muted: #9198a1;
            --border: #3d444d;
            --code-bg: #2b313a;
            --link: #4493f8;
            --quote: #9198a1;
        }
    }
    * { box-sizing: border-box; }
    body {
        margin: 0;
        background: var(--bg);
        color: var(--fg);
        font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
        -webkit-text-size-adjust: 100%;
    }
    article {
        max-width: 760px;
        margin: 0 auto;
        padding: 40px 32px 64px;
        word-wrap: break-word;
    }
    h1, h2, h3, h4, h5, h6 {
        margin: 1.5em 0 0.5em;
        line-height: 1.25;
        font-weight: 600;
    }
    h1 { font-size: 2em; border-bottom: 1px solid var(--border); padding-bottom: 0.3em; }
    h2 { font-size: 1.5em; border-bottom: 1px solid var(--border); padding-bottom: 0.3em; }
    h3 { font-size: 1.25em; }
    h1:first-child { margin-top: 0; }
    p, ul, ol, blockquote, pre, table { margin: 0 0 16px; }
    a { color: var(--link); text-decoration: none; }
    a:hover { text-decoration: underline; }
    code {
        font: 0.875em ui-monospace, "SF Mono", Menlo, Consolas, monospace;
        background: var(--code-bg);
        padding: 0.2em 0.4em;
        border-radius: 6px;
    }
    pre {
        background: var(--code-bg);
        padding: 16px;
        border-radius: 8px;
        overflow-x: auto;
        line-height: 1.45;
    }
    pre code { background: none; padding: 0; font-size: 0.875em; }
    blockquote {
        border-left: 4px solid var(--border);
        padding: 0 1em;
        color: var(--quote);
    }
    ul, ol { padding-left: 2em; }
    li + li { margin-top: 0.25em; }
    img { max-width: 100%; border-radius: 6px; }
    hr {
        border: none;
        border-top: 1px solid var(--border);
        margin: 24px 0;
    }
    table { border-collapse: collapse; display: block; overflow-x: auto; }
    th, td { border: 1px solid var(--border); padding: 6px 13px; }
    th { font-weight: 600; background: var(--code-bg); }
    .frontmatter {
        margin: 0 0 24px;
        padding: 12px 16px;
        background: var(--code-bg);
        border: 1px solid var(--border);
        border-radius: 8px;
        font-size: 0.9em;
        line-height: 1.5;
    }
    .frontmatter dl {
        display: grid;
        grid-template-columns: max-content 1fr;
        gap: 2px 16px;
        margin: 0;
    }
    .frontmatter dt { color: var(--muted); font-weight: 600; word-break: break-word; }
    .frontmatter dd { margin: 0; min-width: 0; word-break: break-word; }
    .frontmatter dd > dl, .frontmatter dd > ul { margin-top: 4px; }
    .frontmatter ul { margin: 0; padding-left: 1.2em; }
    .frontmatter li + li { margin-top: 0; }
    .frontmatter pre {
        margin: 0;
        padding: 0;
        background: none;
        font-size: 0.95em;
        white-space: pre-wrap;
        word-break: break-word;
    }
    .frontmatter a { color: var(--link); word-break: break-all; }
    @media print {
        /* Force a clean, light, full-width layout on paper / in PDFs,
           regardless of the system's dark mode. */
        body { background: #ffffff; color: #1f2328; }
        article { max-width: none; margin: 0; padding: 0; }
        a { color: #0969da; }
        code, pre { background: #f6f8fa; }
        pre { white-space: pre-wrap; word-wrap: break-word; }
        pre code { background: none; }
        th { background: #f6f8fa; }
        h1, h2 { border-bottom-color: #d1d9e0; }
        blockquote { border-left-color: #d1d9e0; color: #59636e; }
        hr { border-top-color: #d1d9e0; }
        .frontmatter { background: #f6f8fa; border-color: #d1d9e0; page-break-inside: avoid; }
        .frontmatter dt { color: #59636e; }
        .frontmatter a { color: #0969da; }
        pre, blockquote, table, img { page-break-inside: avoid; }
        h1, h2, h3, h4, h5, h6 { page-break-after: avoid; }
    }
    """
}
