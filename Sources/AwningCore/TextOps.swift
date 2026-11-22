import Foundation

/// Pure text transforms used by the editor. Kept free of AppKit so they can be unit tested.
public enum TextOps {
    public static let indentUnit = "  "

    // MARK: - List continuation (Return on a list line)

    public enum Continuation: Equatable {
        /// Not a list line: insert a plain newline.
        case none
        /// Insert a newline followed by this marker (e.g. "  - ", "3. ", "- [ ] ").
        case insert(String)
        /// The line is only an empty marker: remove it (ends the list).
        case clearLine
    }

    private static let taskLine = regex(#"^([ \t]*)([-*+]) \[[ xX]\](?: (.*))?$"#)
    private static let bulletLine = regex(#"^([ \t]*)([-*+]) (.*)$"#)
    private static let numberedLine = regex(#"^([ \t]*)(\d{1,9})([.)]) (.*)$"#)
    private static let quoteLine = regex(#"^([ \t]*)>(?: (.*))?$"#)

    /// `line` is the text from the start of the line up to the caret.
    public static func continuation(forLine line: String) -> Continuation {
        let ns = line as NSString
        let all = NSRange(location: 0, length: ns.length)
        func group(_ m: NSTextCheckingResult, _ i: Int) -> String {
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
        if let m = taskLine.firstMatch(in: line, range: all) {
            return isBlank(group(m, 3)) ? .clearLine : .insert(group(m, 1) + group(m, 2) + " [ ] ")
        }
        if let m = bulletLine.firstMatch(in: line, range: all) {
            return isBlank(group(m, 3)) ? .clearLine : .insert(group(m, 1) + group(m, 2) + " ")
        }
        if let m = numberedLine.firstMatch(in: line, range: all) {
            guard !isBlank(group(m, 4)) else { return .clearLine }
            let next = (Int(group(m, 2)) ?? 0) + 1
            return .insert(group(m, 1) + String(next) + group(m, 3) + " ")
        }
        if let m = quoteLine.firstMatch(in: line, range: all) {
            return isBlank(group(m, 2)) ? .clearLine : .insert(group(m, 1) + "> ")
        }
        return .none
    }

    // MARK: - Checkboxes

    private static let openTask = regex(#"^([ \t]*)([-*+]|\d{1,9}[.)]) \[ \]"#)
    private static let doneTask = regex(#"^([ \t]*)([-*+]|\d{1,9}[.)]) \[[xX]\]"#)
    private static let listItem = regex(#"^([ \t]*)([-*+]|\d{1,9}[.)]) "#)

    /// `- [ ] x` → `- [x] x` → `- [ ] x`; `- x` → `- [ ] x`; `x` → `- [ ] x`.
    public static func toggleTask(_ line: String) -> String {
        let ns = line as NSString
        let all = NSRange(location: 0, length: ns.length)
        if openTask.firstMatch(in: line, range: all) != nil {
            return openTask.stringByReplacingMatches(in: line, range: all, withTemplate: "$1$2 [x]")
        }
        if doneTask.firstMatch(in: line, range: all) != nil {
            return doneTask.stringByReplacingMatches(in: line, range: all, withTemplate: "$1$2 [ ]")
        }
        if listItem.firstMatch(in: line, range: all) != nil {
            return listItem.stringByReplacingMatches(in: line, range: all, withTemplate: "$1$2 [ ] ")
        }
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        let rest = line.dropFirst(indent.count)
        return indent + "- [ ] " + rest
    }

    /// Toggles every non-blank line of a block (a single line is toggled even if blank).
    public static func toggleTasks(_ block: String) -> String {
        let lineCount = lines(of: block).count
        return mapLines(block) { line in
            (lineCount > 1 && isBlank(line)) ? line : toggleTask(line)
        }
    }

    // MARK: - Indentation

    public static func indent(_ block: String) -> String {
        mapLines(block) { $0.isEmpty ? $0 : indentUnit + $0 }
    }

    public static func outdent(_ block: String) -> String {
        mapLines(block) { line in
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            let spaces = line.prefix(indentUnit.count).prefix { $0 == " " }.count
            return String(line.dropFirst(spaces))
        }
    }

    // MARK: - Timestamp

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    public static func timestamp(_ date: Date) -> String {
        "--- [\(stampFormatter.string(from: date))] ---"
    }

    /// The text to insert for ⌘D. `preceding` is (up to) the two characters before the caret;
    /// it decides how many newlines are needed so the separator always sits after a blank line.
    public static func timestampBlock(date: Date, preceding: String) -> String {
        let lead: String
        if preceding.isEmpty || preceding.hasSuffix("\n\n") {
            lead = ""
        } else if preceding.hasSuffix("\n") {
            lead = "\n"
        } else {
            lead = "\n\n"
        }
        return lead + timestamp(date) + "\n"
    }

    // MARK: - Stats

    public struct Stats: Equatable {
        public var words: Int
        public var lines: Int
        public init(words: Int, lines: Int) {
            self.words = words
            self.lines = lines
        }
    }

    /// Single pass over UTF-16 code units in chunks. No String copies, cheap even for large files.
    public static func stats(of s: NSString) -> Stats {
        let length = s.length
        guard length > 0 else { return Stats(words: 0, lines: 0) }
        var words = 0
        var newlines = 0
        var inWord = false
        let chunk = 8192
        var buffer = [unichar](repeating: 0, count: chunk)
        var i = 0
        while i < length {
            let n = min(chunk, length - i)
            buffer.withUnsafeMutableBufferPointer { buf in
                s.getCharacters(buf.baseAddress!, range: NSRange(location: i, length: n))
                for k in 0..<n {
                    let c = buf[k]
                    if c == 10 { newlines += 1 }
                    let isSpace = c == 32 || c == 9 || c == 10 || c == 13 || c == 0xA0
                        || c == 0x2028 || c == 0x2029 || c == 0x3000
                    if isSpace {
                        inWord = false
                    } else if !inWord {
                        inWord = true
                        words += 1
                    }
                }
            }
            i += n
        }
        let endsWithNewline = s.character(at: length - 1) == 10
        return Stats(words: words, lines: newlines + (endsWithNewline ? 0 : 1))
    }

    // MARK: - Helpers

    static func isBlank(_ s: String) -> Bool {
        s.allSatisfy { $0 == " " || $0 == "\t" }
    }

    /// Lines of a block, ignoring the empty component after a trailing newline.
    static func lines(of block: String) -> [String] {
        var parts = block.components(separatedBy: "\n")
        if parts.count > 1, parts.last == "" { parts.removeLast() }
        return parts
    }

    static func mapLines(_ block: String, _ transform: (String) -> String) -> String {
        let trailingNewline = block.hasSuffix("\n")
        var out = lines(of: block).map(transform).joined(separator: "\n")
        if trailingNewline { out += "\n" }
        return out
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are compile-time constants; a failure here is a programmer error.
        try! NSRegularExpression(pattern: pattern)
    }
}
