import Foundation
import Testing
@testable import MarkdownViewerCore

private func range(_ location: Int, _ length: Int) -> NSRange {
    NSRange(location: location, length: length)
}

/// Apply a `MarkdownEdit` the way `NSTextView` would, so tests assert on the result.
private func applied(_ edit: MarkdownEdit, to text: String) -> String {
    (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
}

// MARK: - Matching

@Test func findsEveryOccurrence() {
    let matches = TextSearch.matches(of: "cat", in: "cat scatter cat", caseSensitive: true)
    #expect(matches == [range(0, 3), range(5, 3), range(12, 3)])
}

@Test func emptyQueryMatchesNothing() {
    #expect(TextSearch.matches(of: "", in: "anything", caseSensitive: false).isEmpty)
    #expect(TextSearch.matches(of: "x", in: "", caseSensitive: false).isEmpty)
}

@Test func matchingIsCaseInsensitiveByDefault() {
    #expect(TextSearch.matches(of: "md", in: "MD md Md", caseSensitive: false).count == 3)
    #expect(TextSearch.matches(of: "md", in: "MD md Md", caseSensitive: true) == [range(3, 2)])
}

@Test func matchesDoNotOverlap() {
    // "aaaa" contains two non-overlapping "aa", not three overlapping ones.
    #expect(TextSearch.matches(of: "aa", in: "aaaa", caseSensitive: true) == [range(0, 2), range(2, 2)])
}

@Test func offsetsAreUTF16SoAstralCharactersDoNotShiftMatches() {
    let text = "a👍b👍c"           // 👍 is two UTF-16 units
    let matches = TextSearch.matches(of: "👍", in: text, caseSensitive: true)
    #expect(matches == [range(1, 2), range(4, 2)])
    // The offsets must address the same text NSString/NSTextView sees.
    #expect((text as NSString).substring(with: matches[1]) == "👍")
}

@Test func matchesMarkdownMarkupLiterally() {
    let text = "**bold** and *italic*"
    #expect(TextSearch.matches(of: "**", in: text, caseSensitive: true) == [range(0, 2), range(6, 2)])
}

// MARK: - Stepping through matches

@Test func findNextStartsAfterTheSelectionAndWraps() {
    let matches = [range(0, 3), range(10, 3), range(20, 3)]
    // Cursor at the very start → first match.
    #expect(TextSearch.index(after: range(0, 0), in: matches) == 0)
    // The first match is selected → step to the second.
    #expect(TextSearch.index(after: range(0, 3), in: matches) == 1)
    // Past the last match → wrap around to the first.
    #expect(TextSearch.index(after: range(23, 0), in: matches) == 0)
}

@Test func findPreviousStopsBeforeTheSelectionAndWraps() {
    let matches = [range(0, 3), range(10, 3), range(20, 3)]
    #expect(TextSearch.index(before: range(20, 3), in: matches) == 1)
    #expect(TextSearch.index(before: range(10, 3), in: matches) == 0)
    // Nothing before the first match → wrap around to the last.
    #expect(TextSearch.index(before: range(0, 3), in: matches) == 2)
}

@Test func steppingReportsNothingWhenThereAreNoMatches() {
    #expect(TextSearch.index(after: range(0, 0), in: []) == nil)
    #expect(TextSearch.index(before: range(0, 0), in: []) == nil)
}

@Test func currentIndexIdentifiesTheSelectedMatch() {
    let matches = [range(0, 3), range(10, 3)]
    #expect(TextSearch.index(of: range(10, 3), in: matches) == 1)
    // A selection that merely overlaps a match is not "on" it.
    #expect(TextSearch.index(of: range(10, 2), in: matches) == nil)
    #expect(TextSearch.index(of: range(5, 0), in: matches) == nil)
}

// MARK: - Replacing

@Test func replacesASingleMatchAndSelectsTheInsertedText() {
    let text = "one two three"
    let edit = TextSearch.replacement(of: range(4, 3), with: "TWO")
    #expect(applied(edit, to: text) == "one TWO three")
    #expect(edit.selection == range(4, 3))
}

@Test func replaceAllRewritesEveryMatchInOneEdit() {
    let text = "cat scatter cat"
    let edit = TextSearch.replaceAll(of: "cat", with: "dog", in: text, caseSensitive: true)
    #expect(edit != nil)
    #expect(applied(edit!, to: text) == "dog sdogter dog")
    // One edit spanning first→last match, so it is a single undo step.
    #expect(edit!.range == range(0, 15))
}

@Test func replaceAllLeavesTextOutsideTheSpanUntouched() {
    let text = "keep [x] middle [x] keep"
    let edit = TextSearch.replaceAll(of: "[x]", with: "[ ]", in: text, caseSensitive: true)
    #expect(applied(edit!, to: text) == "keep [ ] middle [ ] keep")
    #expect(edit!.range == range(5, 14))       // only the first…last match span
    #expect(edit!.selection == range(19, 0))   // cursor after the rewritten span
}

@Test func replaceAllDoesNotRescanItsOwnOutput() {
    // "a" → "aa" would never terminate if the replacement were re-scanned.
    let text = "a a"
    let edit = TextSearch.replaceAll(of: "a", with: "aa", in: text, caseSensitive: true)
    #expect(applied(edit!, to: text) == "aa aa")
}

@Test func replaceAllIsCaseInsensitiveWhenAsked() {
    let text = "Cat cat CAT"
    let edit = TextSearch.replaceAll(of: "cat", with: "dog", in: text, caseSensitive: false)
    #expect(applied(edit!, to: text) == "dog dog dog")
}

@Test func replaceAllReturnsNilWhenNothingMatches() {
    #expect(TextSearch.replaceAll(of: "zzz", with: "x", in: "abc", caseSensitive: false) == nil)
    #expect(TextSearch.replaceAll(of: "", with: "x", in: "abc", caseSensitive: false) == nil)
}

@Test func replaceAllCanDeleteMatches() {
    let text = "a-b-c"
    let edit = TextSearch.replaceAll(of: "-", with: "", in: text, caseSensitive: true)
    #expect(applied(edit!, to: text) == "abc")
}

@Test func replaceAllKeepsAstralCharactersIntact() {
    let text = "👍 todo 👍 todo"
    let edit = TextSearch.replaceAll(of: "todo", with: "done", in: text, caseSensitive: true)
    #expect(applied(edit!, to: text) == "👍 done 👍 done")
}
