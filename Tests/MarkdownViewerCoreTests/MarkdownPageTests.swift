import Foundation
import Testing
@testable import MarkdownViewerCore

@Test func rendersHeadingAsH1() {
    let html = MarkdownPage.html(from: "# Hello")
    #expect(html.contains("<h1>Hello</h1>"))
}

@Test func rendersFencedCodeBlock() {
    let html = MarkdownPage.html(from: "```\nlet x = 1\n```")
    #expect(html.contains("<pre>"))
    #expect(html.contains("let x = 1"))
}

@Test func outputIsCompleteStyledDocument() {
    let html = MarkdownPage.html(from: "plain text")
    #expect(html.contains("<!DOCTYPE html>"))
    #expect(html.contains("<style>"))
    #expect(html.contains("prefers-color-scheme: dark"))
}

@Test func includesPrintStylesForPDFAndPrinting() {
    let html = MarkdownPage.html(from: "plain text")
    // Print/PDF output must force a light, full-width layout regardless of the
    // system appearance, so the document isn't centred in a narrow column or
    // rendered on a dark background on paper.
    #expect(html.contains("@media print"))
}

@Test func includesLockedDownContentSecurityPolicy() {
    // Untrusted .md files can embed raw HTML (Ink passes it through), so the
    // page must ship a CSP that blocks script execution and remote resource
    // loads while still allowing our own inline styles and inline images.
    let html = MarkdownPage.html(from: "# anything")
    #expect(html.contains("Content-Security-Policy"))
    #expect(html.contains("default-src 'none'"))
    #expect(html.contains("style-src 'unsafe-inline'"))
    #expect(html.contains("img-src data:"))
}

@Test func blocksRemoteImagesByDefault() {
    // Default (and Quick Look) must never permit remote image loads.
    let html = MarkdownPage.html(from: "# anything")
    #expect(html.contains("img-src data:;"))
    #expect(!html.contains("https:"))
}

@Test func allowsRemoteImagesWhenOptedIn() {
    // When the user opts in, remote http/https images are permitted, but
    // scripts and other resource types stay blocked.
    let html = MarkdownPage.html(from: "# anything", allowRemoteImages: true)
    #expect(html.contains("img-src data: https: http:;"))
    #expect(html.contains("default-src 'none'"))
}

@Test func rendersEmphasisAndLists() {
    let html = MarkdownPage.html(from: "- one\n- **two**")
    #expect(html.contains("<ul>"))
    #expect(html.contains("<strong>two</strong>"))
}

@Test func rendersFileContents() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MarkdownPageTests-\(UUID().uuidString).md")
    try Data("# From a file".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let html = try MarkdownPage.html(contentsOf: url)
    #expect(html.contains("<h1>From a file</h1>"))
}

@Test func rendersFrontmatterAsPropertiesCard() {
    let md = """
    ---
    odoo_id: 7863
    name: ISOCELL GmbH & Co KG
    loupe:
      state: Active
      features:
        - Incidents
        - Chat
    ---
    # Body
    """
    let html = MarkdownPage.html(from: md)
    // Structured card with keys, values, nested map and a list.
    #expect(html.contains("class=\"frontmatter\""))
    #expect(html.contains("<dt>odoo_id</dt><dd>7863</dd>"))
    #expect(html.contains("<dt>name</dt>"))
    #expect(html.contains("ISOCELL GmbH &amp; Co KG"))
    #expect(html.contains("<dt>loupe</dt>"))
    #expect(html.contains("<dt>state</dt><dd>Active</dd>"))
    #expect(html.contains("<dt>features</dt>"))
    #expect(html.contains("<li>Incidents</li>"))
    #expect(html.contains("<li>Chat</li>"))
    // The delimiters must NOT leak into the body as <hr>, and the key/value
    // lines must NOT collapse into a paragraph (the original bug).
    #expect(!html.contains("<hr>"))
    #expect(!html.contains("<p>odoo_id"))
    // The body still renders below the card.
    #expect(html.contains("<h1>Body</h1>"))
}

@Test func rendersBodyAfterFrontmatter() {
    let html = MarkdownPage.html(from: "---\ntitle: Hello\n---\n# Heading")
    #expect(html.contains("class=\"frontmatter\""))
    #expect(html.contains("<dt>title</dt><dd>Hello</dd>"))
    #expect(html.contains("<h1>Heading</h1>"))
}

@Test func documentWithoutFrontmatterUnchanged() {
    let html = MarkdownPage.html(from: "# Hello")
    #expect(!html.contains("class=\"frontmatter\""))
    #expect(html.contains("<h1>Hello</h1>"))
}

@Test func midDocumentThematicBreakIsNotFrontmatter() {
    // A `---` that isn't on the first line stays a thematic break, not a card.
    let html = MarkdownPage.html(from: "Intro\n\n---\n\nMore")
    #expect(!html.contains("class=\"frontmatter\""))
    #expect(html.contains("<hr>"))
}

@Test func escapesFrontmatterValues() {
    // Frontmatter is untrusted; values must be HTML-escaped, never injected raw.
    let html = MarkdownPage.html(from: "---\nevil: <script>alert(1)</script>\n---\n# ok")
    #expect(html.contains("&lt;script&gt;"))
    #expect(!html.contains("<script>alert"))
}

@Test func linkifiesFrontmatterURLs() {
    let html = MarkdownPage.html(from: "---\nurl: https://example.com/a?x=1&y=2\n---\n# ok")
    // Bare http(s) URLs become links, with the ampersand escaped in the href.
    #expect(html.contains("<a href=\"https://example.com/a?x=1&amp;y=2\">"))
}

@Test func unterminatedFrontmatterIsNotConsumed() {
    // Without a closing delimiter it's not frontmatter — don't swallow the doc.
    let html = MarkdownPage.html(from: "---\ntitle: x\n# no closing delimiter")
    #expect(!html.contains("class=\"frontmatter\""))
}

@Test func malformedFrontmatterFallsBackToRawBlock() {
    // A construct the simple parser can't consume cleanly (inline map in a
    // sequence) still renders inside the card as raw text — never as a run-on
    // paragraph — and the body below is untouched.
    let html = MarkdownPage.html(from: "---\nlist:\n  - a: 1\n    b: 2\n---\n# ok")
    #expect(html.contains("class=\"frontmatter\""))
    #expect(html.contains("<pre>"))
    #expect(html.contains("<h1>ok</h1>"))
}

@Test func rendersNonUTF8FileWithoutThrowing() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MarkdownPageTests-\(UUID().uuidString).md")
    let latin1 = "# Caf\u{e9}".data(using: .isoLatin1)!
    try latin1.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let html = try MarkdownPage.html(contentsOf: url)
    #expect(html.contains("Caf"))
}
