import Foundation
import Ink

public enum MarkdownPage {
    public static func html(contentsOf url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let markdown = String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)
        return html(from: markdown)
    }

    public static func html(from markdown: String) -> String {
        let body = MarkdownParser().html(from: markdown)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        \(css)
        </style>
        </head>
        <body>
        <article>
        \(body)
        </article>
        </body>
        </html>
        """
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
        pre, blockquote, table, img { page-break-inside: avoid; }
        h1, h2, h3, h4, h5, h6 { page-break-after: avoid; }
    }
    """
}
