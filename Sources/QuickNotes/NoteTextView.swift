import AppKit
import QuickNotesCore

/// The editor. Behaviour is hooked in through standard NSResponder commands
/// (`cancelOperation:`, `insertTab:`, `insertNewline:` …) rather than raw keyCodes, so
/// input methods, dictation and key remapping keep working.
final class NoteTextView: NSTextView {
    var onEscape: (() -> Void)?
    var placeholder = "Start typing…"

    var baseAttributes: [NSAttributedString.Key: Any] = [:] {
        didSet {
            typingAttributes = baseAttributes
            needsDisplay = true
        }
    }

    private var placeholderVisible = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Commands

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func insertTab(_ sender: Any?) {
        let sel = selectedRange()
        if spansMultipleLines(sel) {
            transformSelectedLines(TextOps.indent)
        } else {
            insertText(TextOps.indentUnit, replacementRange: sel)
        }
    }

    override func insertBacktab(_ sender: Any?) {
        transformSelectedLines(TextOps.outdent)
    }

    override func insertNewline(_ sender: Any?) {
        guard let ns = textStorage?.mutableString else { return super.insertNewline(sender) }
        let sel = selectedRange()
        let line = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let beforeCaret = ns.substring(with: NSRange(location: line.location, length: sel.location - line.location))
        switch TextOps.continuation(forLine: beforeCaret) {
        case .none:
            super.insertNewline(sender)
        case .insert(let marker):
            insertText("\n" + marker, replacementRange: sel)
        case .clearLine:
            // Only end the list when the caret is at the end of an empty item.
            let atLineEnd = sel.location == ns.length || ns.character(at: sel.location) == 10
            guard sel.length == 0, atLineEnd else { return super.insertNewline(sender) }
            let markerRange = NSRange(location: line.location, length: sel.location - line.location)
            replace(markerRange, with: "", selecting: NSRange(location: line.location, length: 0))
        }
    }

    func toggleTask() {
        transformSelectedLines(TextOps.toggleTasks, keepCaret: true)
    }

    func insertTimestamp() {
        guard isEditable, let ns = textStorage?.mutableString else { return }
        let sel = selectedRange()
        let start = max(0, sel.location - 2)
        let preceding = ns.substring(with: NSRange(location: start, length: sel.location - start))
        breakUndoCoalescing()
        insertText(TextOps.timestampBlock(date: Date(), preceding: preceding), replacementRange: sel)
        scrollRangeToVisible(selectedRange())
    }

    func moveCaretToEnd() {
        let end = NSRange(location: textStorage?.length ?? 0, length: 0)
        setSelectedRange(end)
        scrollRangeToVisible(end)
    }

    // MARK: - External updates (not undoable user edits, never mark the note dirty)

    /// Text appended to the file by something else. Caret, scroll and undo history are kept.
    func appendExternal(_ text: String) {
        guard let storage = textStorage else { return }
        let oldLength = storage.length
        let sel = selectedRange()
        let caretWasAtEnd = sel.length == 0 && sel.location == oldLength
        storage.append(NSAttributedString(string: text, attributes: baseAttributes))
        breakUndoCoalescing()
        if caretWasAtEnd { moveCaretToEnd() }
        refreshPlaceholder()
    }

    /// Replace everything (initial load / disk version wins). Keeps caret & scroll where possible.
    func replaceAllExternal(_ text: String) {
        let sel = selectedRange()
        let origin = enclosingScrollView?.contentView.bounds.origin
        string = text
        undoManager?.removeAllActions()
        let length = textStorage?.length ?? 0
        setSelectedRange(NSRange(location: min(sel.location, length), length: 0))
        if let origin, let clip = enclosingScrollView?.contentView {
            clip.scroll(to: origin)
            enclosingScrollView?.reflectScrolledClipView(clip)
        }
        refreshPlaceholder()
    }

    // MARK: - Helpers

    private func spansMultipleLines(_ range: NSRange) -> Bool {
        guard range.length > 0, let ns = textStorage?.mutableString else { return false }
        return ns.lineRange(for: NSRange(location: range.location, length: 0)) != ns.lineRange(for: range)
    }

    private func transformSelectedLines(_ transform: (String) -> String, keepCaret: Bool = false) {
        guard isEditable, let ns = textStorage?.mutableString else { return }
        let sel = selectedRange()
        let lines = ns.lineRange(for: sel)
        let old = ns.substring(with: lines)
        let new = transform(old)
        guard new != old else { return }
        let newLength = (new as NSString).length
        let contentLength = newLength - (new.hasSuffix("\n") ? 1 : 0)
        let selection: NSRange
        if keepCaret && sel.length == 0 {
            let shifted = sel.location + (newLength - lines.length)
            selection = NSRange(location: min(max(shifted, lines.location), lines.location + contentLength), length: 0)
        } else {
            selection = NSRange(location: lines.location, length: contentLength)
        }
        replace(lines, with: new, selecting: selection)
    }

    /// An undoable programmatic edit that flows through the normal change notifications.
    private func replace(_ range: NSRange, with text: String, selecting selection: NSRange) {
        breakUndoCoalescing()
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: baseAttributes))
        didChangeText()
        setSelectedRange(selection)
        scrollRangeToVisible(selection)
    }

    // MARK: - Placeholder

    override func didChangeText() {
        super.didChangeText()
        refreshPlaceholder()
    }

    func refreshPlaceholder() {
        let empty = (textStorage?.length ?? 0) == 0
        if empty != placeholderVisible {
            placeholderVisible = empty
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard (textStorage?.length ?? 0) == 0, !hasMarkedText() else { return }
        let font = baseAttributes[.font] as? NSFont ?? Theme.mono(14)
        let origin = NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
                             y: textContainerInset.height)
        (placeholder as NSString).draw(at: origin, withAttributes: [.font: font, .foregroundColor: Theme.faint])
    }
}
