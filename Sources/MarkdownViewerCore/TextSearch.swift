import Foundation

/// Plain-text find & replace over the raw Markdown source, used by the document
/// window's find bar while editing.
///
/// Pure and AppKit-free, like `MarkdownEditor`: it takes the text plus the current
/// selection and hands back UTF-16 ranges / a `MarkdownEdit`, which the app applies
/// to the `NSTextView` verbatim. Matching is deliberately *literal* (`.literal`), so
/// a match is always exactly as long as the query in UTF-16 units — no canonical
/// re-composition silently shifting the offsets of everything after it.
///
/// The rendered preview does **not** go through here: it uses WebKit's own
/// find-in-page (see `FindController`), because there is no mapping from source
/// offsets to positions in the rendered page.
public enum TextSearch {

    /// Every non-overlapping occurrence of `query` in `text`, left to right, as
    /// UTF-16 ranges. An empty query has no matches.
    public static func matches(of query: String, in text: String, caseSensitive: Bool) -> [NSRange] {
        let needleLength = (query as NSString).length
        guard needleLength > 0 else { return [] }

        let haystack = text as NSString
        var options: NSString.CompareOptions = [.literal]
        if !caseSensitive { options.insert(.caseInsensitive) }

        var found: [NSRange] = []
        var start = 0
        while start < haystack.length {
            let scope = NSRange(location: start, length: haystack.length - start)
            let match = haystack.range(of: query, options: options, range: scope)
            guard match.location != NSNotFound else { break }
            found.append(match)
            // Non-overlapping: resume after this match. `max(1, …)` guards against
            // a zero-length match wedging the loop (it can't happen with a
            // non-empty literal query, but the loop must not depend on that).
            start = match.location + max(1, match.length)
        }
        return found
    }

    /// Index of the match to jump to for "find next", starting after `selection`
    /// and wrapping around to the first match. `nil` only when there is nothing
    /// to find.
    public static func index(after selection: NSRange, in matches: [NSRange]) -> Int? {
        guard !matches.isEmpty else { return nil }
        let from = NSMaxRange(selection)
        return matches.firstIndex { $0.location >= from } ?? 0
    }

    /// Index of the match to jump to for "find previous": the last one that ends
    /// at or before the selection starts, wrapping around to the last match.
    public static func index(before selection: NSRange, in matches: [NSRange]) -> Int? {
        guard !matches.isEmpty else { return nil }
        let limit = selection.location
        return matches.lastIndex { NSMaxRange($0) <= limit } ?? (matches.count - 1)
    }

    /// Index of the match the selection currently *is*, if any. Used to show
    /// "3 of 12" and to make Replace act on the highlighted match only.
    public static func index(of selection: NSRange, in matches: [NSRange]) -> Int? {
        matches.firstIndex(of: selection)
    }

    /// Replace a single match, leaving the inserted text selected so the caller
    /// can show where it landed.
    public static func replacement(of match: NSRange, with replacement: String) -> MarkdownEdit {
        MarkdownEdit(range: match,
                     replacement: replacement,
                     selection: NSRange(location: match.location,
                                        length: (replacement as NSString).length))
    }

    /// Replace every match in one edit — a single range spanning the first match
    /// through the last, so it is one undo step and one document change. `nil`
    /// when there is nothing to replace.
    ///
    /// Building the replacement from the *original* text also means a replacement
    /// containing the query (`a` → `aa`) is not re-scanned, so it can't run away.
    public static func replaceAll(of query: String,
                                  with replacement: String,
                                  in text: String,
                                  caseSensitive: Bool) -> MarkdownEdit? {
        let found = matches(of: query, in: text, caseSensitive: caseSensitive)
        guard let first = found.first, let last = found.last else { return nil }

        let source = text as NSString
        let span = NSRange(location: first.location, length: NSMaxRange(last) - first.location)

        var rebuilt = ""
        var cursor = first.location
        for match in found {
            rebuilt += source.substring(with: NSRange(location: cursor, length: match.location - cursor))
            rebuilt += replacement
            cursor = NSMaxRange(match)
        }

        // Cursor collapsed at the end of the rewritten span.
        let end = first.location + (rebuilt as NSString).length
        return MarkdownEdit(range: span, replacement: rebuilt,
                            selection: NSRange(location: end, length: 0))
    }
}
