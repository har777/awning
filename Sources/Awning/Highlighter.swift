import AppKit

/// Light, plain-text-friendly styling: timestamp separators, `#` headings, list markers,
/// checkboxes (done items dimmed + struck through), `inline code` and clickable links.
/// The file stays plain text. Only the edited paragraphs are re-styled on each keystroke,
/// and only that paragraph's text is ever copied out of the storage.
final class Highlighter: NSObject, NSTextStorageDelegate {
    private(set) var baseAttributes: [NSAttributedString.Key: Any] = [:]
    private var boldFont: NSFont

    private static let marker = regex(#"^[ \t]*((?:[-*+]|\d{1,9}[.)])(?: \[[ xX]\])?|>)(?= |$)"#)
    private static let inlineCode = regex(#"`[^`\n]+`"#)
    private static let heading = regex(#"^#{1,6}[ \t].*$"#)
    private static let separator = regex(#"^-{3,} \[[^\]\n]*\] -{3,}[ \t]*$"#)
    private static let doneTask = regex(#"^[ \t]*(?:[-*+]|\d{1,9}[.)]) \[[xX]\].*$"#)
    // Explicit URLs only. (NSDataDetector is slower and links things like "readme.md".)
    private static let link = regex(#"\bhttps?://[^\s<>"'`]+[^\s<>"'`.,;:!?)\]]"#)

    init(fontSize: CGFloat) {
        boldFont = Theme.mono(fontSize, .bold)
        super.init()
        setFontSize(fontSize)
    }

    func setFontSize(_ size: CGFloat) {
        boldFont = Theme.mono(size, .bold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = round(size * 0.28)
        baseAttributes = [.font: Theme.mono(size), .foregroundColor: Theme.text, .paragraphStyle: paragraph]
    }

    func highlightAll(_ storage: NSTextStorage) {
        storage.beginEditing()
        apply(to: storage, in: NSRange(location: 0, length: storage.length))
        storage.endEditing()
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        apply(to: textStorage, in: textStorage.mutableString.paragraphRange(for: editedRange))
    }

    private func apply(to storage: NSTextStorage, in range: NSRange) {
        guard range.length > 0 else { return }
        storage.setAttributes(baseAttributes, range: range)

        let text = storage.mutableString.substring(with: range)
        let local = NSRange(location: 0, length: range.length)
        func each(_ re: NSRegularExpression, group: Int = 0, _ body: (NSRange) -> Void) {
            re.enumerateMatches(in: text, range: local) { m, _, _ in
                guard let r = m?.range(at: group), r.location != NSNotFound else { return }
                body(NSRange(location: r.location + range.location, length: r.length))
            }
        }

        // Later rules win where they overlap (a done task dims its accent-coloured marker).
        each(Self.marker, group: 1) { storage.addAttribute(.foregroundColor, value: Theme.accent, range: $0) }
        each(Self.inlineCode) { storage.addAttribute(.foregroundColor, value: Theme.code, range: $0) }
        each(Self.heading) { storage.addAttributes([.foregroundColor: Theme.heading, .font: boldFont], range: $0) }
        each(Self.separator) { storage.addAttributes([.foregroundColor: Theme.accent, .font: boldFont], range: $0) }
        each(Self.doneTask) {
            storage.addAttributes([.foregroundColor: Theme.faint,
                                   .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                   .strikethroughColor: Theme.faint], range: $0)
        }
        each(Self.link) { r in
            if let url = URL(string: storage.mutableString.substring(with: r)) {
                storage.addAttribute(.link, value: url, range: r)
            }
        }
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }
}
