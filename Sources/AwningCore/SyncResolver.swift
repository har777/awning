import Foundation

/// What to do when the file on disk no longer matches what we last saved.
public enum SyncAction: Equatable {
    /// Disk matches our last save (usually our own write echoing back). Nothing to do.
    case none
    /// Disk already equals the editor's unsaved text. Just mark it saved.
    case adopt
    /// Something appended to the file (`echo … >> notes.txt`). Append these bytes to the
    /// editor, which keeps the caret, scroll position, undo history and any unsaved edits.
    case append(Data)
    /// The editor has no unsaved edits, so load the disk version.
    case replace
    /// The editor has unsaved edits *and* disk changed in a way we can't merge.
    /// The caller keeps the editor's text and backs up the disk version.
    case conflict
}

public enum SyncResolver {
    /// - Parameters:
    ///   - base: what we last read from or wrote to disk (`nil` if the file was missing).
    ///   - disk: what is on disk now.
    ///   - editor: the editor's current text, or `nil` if it has no unsaved edits.
    public static func resolve(base: Data?, disk: Data, editor: Data?) -> SyncAction {
        if let base, base == disk { return .none }
        if let editor, editor == disk { return .adopt }
        if let base, !base.isEmpty, disk.count > base.count, disk.hasPrefix(base) {
            return .append(Data(disk[(disk.startIndex + base.count)...]))
        }
        return editor == nil ? .replace : .conflict
    }
}
