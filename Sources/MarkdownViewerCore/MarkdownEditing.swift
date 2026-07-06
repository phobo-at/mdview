import Foundation

/// A Markdown formatting action requested from the edit-mode toolbar / Format menu.
public enum MarkdownFormat: Equatable {
    case bold, italic, strikethrough, inlineCode
    case heading(Int)                 // 1...6
    case bulletList, numberedList, quote
    case codeBlock, link, horizontalRule, table
}

/// The result of a formatting action: a single range replacement plus where the
/// selection/cursor should land afterwards. Offsets are UTF-16 (NSRange), matching
/// what `NSTextView` reports and expects, so the app can apply it verbatim.
public struct MarkdownEdit: Equatable {
    public let range: NSRange        // range in the ORIGINAL text to replace
    public let replacement: String
    public let selection: NSRange    // desired selection in the NEW text

    public init(range: NSRange, replacement: String, selection: NSRange) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }
}

/// Pure Markdown source transformations for the raw editor. Given the text and the
/// current selection, `edit` returns a tight range replacement — no side effects,
/// no AppKit — so it is fully unit-testable and shared conceptually with the way
/// `MarkdownPage` keeps the real logic in the core.
public enum MarkdownEditor {
    public static func edit(_ format: MarkdownFormat, in text: String, selection: NSRange) -> MarkdownEdit {
        let ns = text as NSString
        let sel = clamp(selection, length: ns.length)
        switch format {
        case .bold:           return inline(ns, sel, "**", "**")
        case .italic:         return inline(ns, sel, "*", "*")
        case .strikethrough:  return inline(ns, sel, "~~", "~~")
        case .inlineCode:     return inline(ns, sel, "`", "`")
        case .heading(let n): return heading(ns, sel, level: max(1, min(6, n)))
        case .bulletList:     return linePrefix(ns, sel, marker: .bullet)
        case .numberedList:   return linePrefix(ns, sel, marker: .numbered)
        case .quote:          return linePrefix(ns, sel, marker: .quote)
        case .codeBlock:      return codeBlock(ns, sel)
        case .link:           return link(ns, sel)
        case .horizontalRule: return insertBlock(ns, sel, "---\n")
        case .table:          return table(ns, sel)
        }
    }
}

// MARK: - Inline wrapping (bold / italic / strikethrough / inline code)

/// Wrap the selection in `prefix`…`suffix`. If the selection is already wrapped
/// (markers inside the selection, or sitting immediately outside it), unwrap it
/// instead — so the same action toggles. Empty selection inserts the markers with
/// the cursor between them.
private func inline(_ ns: NSString, _ sel: NSRange, _ prefix: String, _ suffix: String) -> MarkdownEdit {
    let p = (prefix as NSString).length
    let s = (suffix as NSString).length

    guard sel.length > 0 else {
        let replacement = prefix + suffix
        return MarkdownEdit(range: sel, replacement: replacement,
                            selection: NSRange(location: sel.location + p, length: 0))
    }

    let selected = ns.substring(with: sel)
    let sns = selected as NSString
    // Our markers are runs of a single character (`*`, `**`, `~~`, `` ` ``). A
    // shorter marker must not match *inside* a longer run of the same char — else
    // Italic on `**bold**` would strip one `*` and silently downgrade it. So an
    // unwrap only fires when the matched run is maximal (bounded by a different
    // char on the far side).
    let pc = (prefix as NSString).character(at: 0)
    let sc = (suffix as NSString).character(at: 0)

    // Case A: the selection itself includes the markers → strip them.
    if sns.length >= p + s,
       sns.substring(to: p) == prefix,
       sns.substring(from: sns.length - s) == suffix,
       sns.length == p + s || (sns.character(at: p) != pc && sns.character(at: sns.length - s - 1) != sc),
       !(prefix == suffix && sns.length == p) {
        let inner = sns.substring(with: NSRange(location: p, length: sns.length - p - s))
        return MarkdownEdit(range: sel, replacement: inner,
                            selection: NSRange(location: sel.location, length: (inner as NSString).length))
    }

    // Case B: the markers sit immediately outside the selection → strip them.
    let outerStart = sel.location - p
    let outerEnd = sel.location + sel.length + s
    if outerStart >= 0, outerEnd <= ns.length,
       ns.substring(with: NSRange(location: outerStart, length: p)) == prefix,
       ns.substring(with: NSRange(location: sel.location + sel.length, length: s)) == suffix,
       outerStart == 0 || ns.character(at: outerStart - 1) != pc,
       outerEnd == ns.length || ns.character(at: outerEnd) != sc {
        return MarkdownEdit(range: NSRange(location: outerStart, length: outerEnd - outerStart),
                            replacement: selected,
                            selection: NSRange(location: outerStart, length: sns.length))
    }

    // Otherwise wrap.
    return MarkdownEdit(range: sel, replacement: prefix + selected + suffix,
                        selection: NSRange(location: sel.location + p, length: sns.length))
}

// MARK: - Headings

private func heading(_ ns: NSString, _ sel: NSRange, level: Int) -> MarkdownEdit {
    let marker = String(repeating: "#", count: level) + " "
    return transformLines(ns, sel) { lines in
        let single = lines.count == 1
        let nonEmpty = lines.filter { !$0.isEmpty }
        let allAtLevel = !nonEmpty.isEmpty && nonEmpty.allSatisfy { headingLevel($0) == level }
        if allAtLevel {
            return lines.map(stripHeading)          // toggle off
        }
        // Skip blank lines across a multi-line selection (no empty "## " headings),
        // but always mark a lone empty line so a fresh cursor gets its heading.
        return lines.map { ($0.isEmpty && !single) ? $0 : marker + stripHeading($0) }
    }
}

/// The heading level of a line (1…6), or 0 if it isn't an ATX heading.
private func headingLevel(_ line: String) -> Int {
    let chars = Array(line)
    var count = 0
    while count < chars.count, chars[count] == "#" { count += 1 }
    if count > 0, count <= 6, count < chars.count, chars[count] == " " { return count }
    return 0
}

private func stripHeading(_ line: String) -> String {
    let level = headingLevel(line)
    return level > 0 ? String(line.dropFirst(level + 1)) : line
}

// MARK: - Line prefixes (bullet / numbered / quote)

private enum LineMarker { case bullet, numbered, quote }

private func linePrefix(_ ns: NSString, _ sel: NSRange, marker: LineMarker) -> MarkdownEdit {
    return transformLines(ns, sel) { lines in
        let single = lines.count == 1
        let nonEmpty = lines.filter { !$0.isEmpty }
        let allHave = !nonEmpty.isEmpty && nonEmpty.allSatisfy { hasMarker($0, marker) }
        if allHave {
            return lines.map { removeMarker($0, marker) }   // toggle off
        }
        // Add. Skip blank lines when the block spans several (avoids stray "- "),
        // but always act on a lone empty line so the cursor gets a fresh bullet.
        var n = 0
        return lines.map { line in
            if line.isEmpty && !single { return line }
            switch marker {
            case .bullet: return "- " + line
            case .quote:  return "> " + line
            case .numbered:
                n += 1
                return "\(n). " + line
            }
        }
    }
}

private func hasMarker(_ line: String, _ marker: LineMarker) -> Bool {
    switch marker {
    case .bullet:   return line.hasPrefix("- ")
    case .quote:    return line.hasPrefix("> ")
    case .numbered: return numberedPrefixLength(line) != nil
    }
}

private func removeMarker(_ line: String, _ marker: LineMarker) -> String {
    switch marker {
    case .bullet:   return line.hasPrefix("- ") ? String(line.dropFirst(2)) : line
    case .quote:    return line.hasPrefix("> ") ? String(line.dropFirst(2)) : line
    case .numbered:
        if let len = numberedPrefixLength(line) { return String(line.dropFirst(len)) }
        return line
    }
}

/// Length of a leading `\d+. ` ordered-list marker, or nil if the line has none.
private func numberedPrefixLength(_ line: String) -> Int? {
    let chars = Array(line)
    var i = 0
    // ASCII digits only — `Character.isNumber` also matches Arabic-Indic etc.,
    // which aren't Markdown ordered-list markers.
    while i < chars.count, chars[i].isASCII, chars[i].isNumber { i += 1 }
    guard i > 0, i < chars.count, chars[i] == ".", i + 1 < chars.count, chars[i + 1] == " " else { return nil }
    return i + 2
}

// MARK: - Blocks (code block / link / horizontal rule / table)

private func codeBlock(_ ns: NSString, _ sel: NSRange) -> MarkdownEdit {
    let lineRange = ns.lineRange(for: sel)
    let block = ns.substring(with: lineRange)
    let trailingNewline = block.hasSuffix("\n")
    let content = trailingNewline ? String(block.dropLast()) : block

    var replacement = "```\n" + content + "\n```"
    if trailingNewline { replacement += "\n" }

    let contentStart = lineRange.location + ("```\n" as NSString).length
    let selection = content.isEmpty
        ? NSRange(location: contentStart, length: 0)
        : NSRange(location: contentStart, length: (content as NSString).length)
    return MarkdownEdit(range: lineRange, replacement: replacement, selection: selection)
}

private func link(_ ns: NSString, _ sel: NSRange) -> MarkdownEdit {
    if sel.length > 0 {
        let selected = ns.substring(with: sel)
        let replacement = "[\(selected)](url)"
        let urlLoc = sel.location + 1 + (selected as NSString).length + 2   // past "[" + text + "]("
        return MarkdownEdit(range: sel, replacement: replacement,
                            selection: NSRange(location: urlLoc, length: 3)) // select "url"
    }
    return MarkdownEdit(range: sel, replacement: "[text](url)",
                        selection: NSRange(location: sel.location + 1, length: 4)) // select "text"
}

private func table(_ ns: NSString, _ sel: NSRange) -> MarkdownEdit {
    let body = "| Column 1 | Column 2 |\n| --- | --- |\n|  |  |\n"
    return insertBlock(ns, sel, body,
                       // select "Column 1" so the header is ready to overtype
                       innerSelection: { start in NSRange(location: start + 2, length: 8) })
}

/// Insert `text` on its own line just after the cursor (or after any selection —
/// it inserts, so selected text is kept, not replaced). Adds a leading newline
/// unless the insertion point already sits at the start of a line. By default the
/// cursor lands just after the inserted block; `innerSelection` can override where
/// the selection ends up (relative to the block's start).
private func insertBlock(_ ns: NSString, _ sel: NSRange, _ text: String,
                         innerSelection: ((Int) -> NSRange)? = nil) -> MarkdownEdit {
    let insertAt = sel.location + sel.length
    let atLineStart = insertAt == 0 || ns.character(at: insertAt - 1) == 10 // '\n'
    let prefix = atLineStart ? "" : "\n"
    let replacement = prefix + text
    let blockStart = insertAt + (prefix as NSString).length
    let selection = innerSelection?(blockStart)
        ?? NSRange(location: insertAt + (replacement as NSString).length, length: 0)
    return MarkdownEdit(range: NSRange(location: insertAt, length: 0), replacement: replacement, selection: selection)
}

// MARK: - Shared line helper

/// Apply a per-line transform to every line the selection touches (via
/// `lineRange`), replacing that whole line block in one edit. A non-empty original
/// selection re-selects the transformed block; a collapsed cursor lands at the end
/// of the transformed content (before the trailing newline).
private func transformLines(_ ns: NSString, _ sel: NSRange,
                            _ transform: ([String]) -> [String]) -> MarkdownEdit {
    let lineRange = ns.lineRange(for: sel)
    let block = ns.substring(with: lineRange)
    let trailingNewline = block.hasSuffix("\n")
    var lines = block.components(separatedBy: "\n")
    if trailingNewline { lines.removeLast() }

    var replacement = transform(lines).joined(separator: "\n")
    if trailingNewline { replacement += "\n" }

    let contentLength = (replacement as NSString).length - (trailingNewline ? 1 : 0)
    let selection = sel.length == 0
        ? NSRange(location: lineRange.location + contentLength, length: 0)
        : NSRange(location: lineRange.location, length: contentLength)
    return MarkdownEdit(range: lineRange, replacement: replacement, selection: selection)
}

private func clamp(_ r: NSRange, length: Int) -> NSRange {
    let loc = max(0, min(r.location, length))
    return NSRange(location: loc, length: max(0, min(r.length, length - loc)))
}
