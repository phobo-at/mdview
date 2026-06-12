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

@Test func rendersNonUTF8FileWithoutThrowing() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MarkdownPageTests-\(UUID().uuidString).md")
    let latin1 = "# Caf\u{e9}".data(using: .isoLatin1)!
    try latin1.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let html = try MarkdownPage.html(contentsOf: url)
    #expect(html.contains("Caf"))
}
