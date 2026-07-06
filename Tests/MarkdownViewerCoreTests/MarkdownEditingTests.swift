import Foundation
import Testing
@testable import MarkdownViewerCore

/// Apply a `MarkdownEdit` to `text` the same way `NSTextView` would, so tests can
/// assert on the resulting document string.
private func applied(_ edit: MarkdownEdit, to text: String) -> String {
    (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
}

private func range(_ location: Int, _ length: Int) -> NSRange {
    NSRange(location: location, length: length)
}

// MARK: - Inline wrapping

@Test func wrapsSelectionInBold() {
    let edit = MarkdownEditor.edit(.bold, in: "hello world", selection: range(6, 5))
    #expect(applied(edit, to: "hello world") == "hello **world**")
    // Selection lands on the inner text, so a further edit replaces "world".
    #expect(edit.selection == range(8, 5))
}

@Test func emptySelectionInsertsMarkersWithCursorBetween() {
    let edit = MarkdownEditor.edit(.italic, in: "ab", selection: range(1, 0))
    #expect(applied(edit, to: "ab") == "a**b")   // "*" + "*" inserted at offset 1
    #expect(edit.selection == range(2, 0))       // cursor between the two markers
}

@Test func boldTogglesOffWhenSelectionIncludesMarkers() {
    let text = "**word**"
    let edit = MarkdownEditor.edit(.bold, in: text, selection: range(0, 8))
    #expect(applied(edit, to: text) == "word")
    #expect(edit.selection == range(0, 4))
}

@Test func boldTogglesOffWhenMarkersSitOutsideSelection() {
    let text = "**word**"
    // Select just "word" (offset 2, length 4); the ** are immediately outside.
    let edit = MarkdownEditor.edit(.bold, in: text, selection: range(2, 4))
    #expect(applied(edit, to: text) == "word")
    #expect(edit.selection == range(0, 4))
}

@Test func wrapsSelectionInInlineCode() {
    let edit = MarkdownEditor.edit(.inlineCode, in: "run x now", selection: range(4, 1))
    #expect(applied(edit, to: "run x now") == "run `x` now")
}

@Test func wrapsSelectionInStrikethrough() {
    let edit = MarkdownEditor.edit(.strikethrough, in: "old", selection: range(0, 3))
    #expect(applied(edit, to: "old") == "~~old~~")
}

// MARK: - Headings

@Test func appliesHeadingToLine() {
    let edit = MarkdownEditor.edit(.heading(2), in: "Title", selection: range(0, 0))
    #expect(applied(edit, to: "Title") == "## Title")
}

@Test func headingTogglesOffAtSameLevel() {
    let text = "## Title"
    let edit = MarkdownEditor.edit(.heading(2), in: text, selection: range(3, 0))
    #expect(applied(edit, to: text) == "Title")
}

@Test func headingReplacesExistingLevel() {
    let text = "# Title"
    let edit = MarkdownEditor.edit(.heading(3), in: text, selection: range(0, 0))
    #expect(applied(edit, to: text) == "### Title")
}

// MARK: - Lists & quote

@Test func addsBulletToEverySelectedLine() {
    let text = "one\ntwo"
    let edit = MarkdownEditor.edit(.bulletList, in: text, selection: range(0, 7))
    #expect(applied(edit, to: text) == "- one\n- two")
}

@Test func bulletTogglesOffWhenAllLinesHaveIt() {
    let text = "- one\n- two"
    let edit = MarkdownEditor.edit(.bulletList, in: text, selection: range(0, text.utf16.count))
    #expect(applied(edit, to: text) == "one\ntwo")
}

@Test func numbersSelectedLinesSequentially() {
    let text = "a\nb\nc"
    let edit = MarkdownEditor.edit(.numberedList, in: text, selection: range(0, 5))
    #expect(applied(edit, to: text) == "1. a\n2. b\n3. c")
}

@Test func numberedListTogglesOff() {
    let text = "1. a\n2. b"
    let edit = MarkdownEditor.edit(.numberedList, in: text, selection: range(0, text.utf16.count))
    #expect(applied(edit, to: text) == "a\nb")
}

@Test func addsQuotePrefix() {
    let edit = MarkdownEditor.edit(.quote, in: "cited", selection: range(0, 0))
    #expect(applied(edit, to: "cited") == "> cited")
}

@Test func bulletOnLoneEmptyLineInsertsMarker() {
    let edit = MarkdownEditor.edit(.bulletList, in: "", selection: range(0, 0))
    #expect(applied(edit, to: "") == "- ")
    #expect(edit.selection == range(2, 0))   // cursor after the marker
}

// MARK: - Code block

@Test func fencesSelectedLines() {
    let text = "let x = 1"
    let edit = MarkdownEditor.edit(.codeBlock, in: text, selection: range(0, text.utf16.count))
    #expect(applied(edit, to: text) == "```\nlet x = 1\n```")
    #expect(edit.selection == range(4, 9))   // selects the fenced content
}

@Test func emptyCodeBlockPutsCursorInside() {
    let edit = MarkdownEditor.edit(.codeBlock, in: "", selection: range(0, 0))
    #expect(applied(edit, to: "") == "```\n\n```")
    #expect(edit.selection == range(4, 0))
}

// MARK: - Link

@Test func linkWrapsSelectionAndSelectsURL() {
    let text = "see docs"
    let edit = MarkdownEditor.edit(.link, in: text, selection: range(4, 4))
    #expect(applied(edit, to: text) == "see [docs](url)")
    // Selection targets "url" so the user can type the destination immediately.
    let result = applied(edit, to: text) as NSString
    #expect(result.substring(with: edit.selection) == "url")
}

@Test func linkWithoutSelectionSelectsTextPlaceholder() {
    let edit = MarkdownEditor.edit(.link, in: "", selection: range(0, 0))
    #expect(applied(edit, to: "") == "[text](url)")
    let result = applied(edit, to: "") as NSString
    #expect(result.substring(with: edit.selection) == "text")
}

// MARK: - Horizontal rule & table

@Test func horizontalRuleInsertsOnOwnLine() {
    let text = "para"
    let edit = MarkdownEditor.edit(.horizontalRule, in: text, selection: range(4, 0))
    // Not at line start, so a newline is prepended.
    #expect(applied(edit, to: text) == "para\n---\n")
}

@Test func horizontalRuleAtLineStartHasNoLeadingNewline() {
    let edit = MarkdownEditor.edit(.horizontalRule, in: "", selection: range(0, 0))
    #expect(applied(edit, to: "") == "---\n")
}

@Test func tableInsertsScaffoldAndSelectsFirstHeader() {
    let edit = MarkdownEditor.edit(.table, in: "", selection: range(0, 0))
    let result = applied(edit, to: "")
    #expect(result == "| Column 1 | Column 2 |\n| --- | --- |\n|  |  |\n")
    #expect((result as NSString).substring(with: edit.selection) == "Column 1")
}

// MARK: - Review-fix regressions

// A shorter marker must not match inside a longer run of the same char: Italic on
// bold text nests instead of stripping a `*` and downgrading bold to italic.
@Test func italicOnBoldNestsInsteadOfStripping() {
    let text = "**hi**"
    let edit = MarkdownEditor.edit(.italic, in: text, selection: range(2, 2)) // inner "hi"
    #expect(applied(edit, to: text) == "***hi***")
}

// The common toggle (double-click a word inside **word**, press ⌘B) still unwraps.
@Test func boldUnwrapsFromInnerSelection() {
    let text = "**hi**"
    let edit = MarkdownEditor.edit(.bold, in: text, selection: range(2, 2))
    #expect(applied(edit, to: text) == "hi")
}

@Test func italicUnwrapsPlainItalic() {
    let text = "*hi*"
    let edit = MarkdownEditor.edit(.italic, in: text, selection: range(1, 2))
    #expect(applied(edit, to: text) == "hi")
}

// Inserting a rule/table keeps the current selection instead of deleting it.
@Test func horizontalRuleKeepsSelectedText() {
    let text = "keep"
    let edit = MarkdownEditor.edit(.horizontalRule, in: text, selection: range(0, 4))
    #expect(applied(edit, to: text) == "keep\n---\n")
}

@Test func tableKeepsSelectedText() {
    let text = "data"
    let edit = MarkdownEditor.edit(.table, in: text, selection: range(0, 4))
    #expect(applied(edit, to: text).hasPrefix("data\n| Column 1 | Column 2 |"))
}

// Headings skip blank lines across a multi-line selection (no empty "## ").
@Test func headingSkipsBlankLinesInSelection() {
    let text = "a\n\nc"
    let edit = MarkdownEditor.edit(.heading(2), in: text, selection: range(0, 4))
    #expect(applied(edit, to: text) == "## a\n\n## c")
}

// A line starting with a non-ASCII digit isn't a Markdown ordered-list item, so
// the numbered-list action adds a marker rather than stripping the line's text.
@Test func numberedListIgnoresNonASCIIDigitPrefix() {
    let text = "\u{0662}. x"   // Arabic-Indic 2 + ". x"
    let edit = MarkdownEditor.edit(.numberedList, in: text, selection: range(0, (text as NSString).length))
    #expect(applied(edit, to: text) == "1. \u{0662}. x")
}
