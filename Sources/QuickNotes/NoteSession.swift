import AppKit
import QuickNotesCore

enum NoteStatus: Equatable {
    case saved
    case edited
    case missing
    case readOnly(String)
    case error(String)
    case conflict(URL)
}

/// Owns the link between the editor and the file: dirty tracking, debounced saving,
/// and merging changes made on disk by anything else.
///
/// Invariant: `base` is exactly what we last read from or wrote to disk. Every external
/// change is compared against it, so our own writes are recognised and nothing is lost.
final class NoteSession {
    var onStatus: ((NoteStatus) -> Void)?
    /// The editor text was changed from disk (not by typing).
    var onExternalChange: (() -> Void)?

    private(set) var file: NoteFile
    private(set) var isDirty = false
    private(set) var isReadOnly = false
    private(set) var status: NoteStatus = .saved

    private unowned let textView: NoteTextView
    private var base: Data?
    private var dirtySince: Date?
    private var saveTimer: Timer?
    private var watcher: FileWatcher?

    /// Save this long after the last keystroke…
    private let idleDelay: TimeInterval = 0.4
    /// …but never let unsaved typing get older than this.
    private let maxDelay: TimeInterval = 3

    init(url: URL, textView: NoteTextView) {
        self.file = NoteFile(url: url)
        self.textView = textView
    }

    // MARK: - Lifecycle

    func open() {
        watcher?.stop()
        saveTimer?.invalidate()
        isDirty = false
        dirtySince = nil
        base = nil

        switch file.read() {
        case .contents(let data):
            load(data)
        case .missing:
            setReadOnly(false)
            textView.replaceAllExternal("")
            do {
                try file.write(Data(), replacing: nil)
                base = Data()
                report(.saved)
            } catch {
                report(.missing)
            }
        case .failure(let error):
            textView.replaceAllExternal("")
            enterReadOnly("Can't read file: \(error.localizedDescription)")
        }
        textView.moveCaretToEnd()
        onExternalChange?()

        watcher = FileWatcher(url: file.url) { [weak self] in self?.syncFromDisk() }
        watcher?.start()
    }

    func switchTo(_ url: URL) {
        flush()
        file = NoteFile(url: url)
        open()
    }

    // MARK: - Editing

    func textDidChange() {
        guard !isReadOnly else { return }
        if !isDirty {
            isDirty = true
            dirtySince = Date()
        }
        report(.edited)
        scheduleSave()
    }

    /// Save now if there is anything to save.
    func flush() {
        saveTimer?.invalidate()
        saveTimer = nil
        save()
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        let now = Date()
        let deadline = min(now.addingTimeInterval(idleDelay), (dirtySince ?? now).addingTimeInterval(maxDelay))
        saveAfter(deadline.timeIntervalSince(now))
    }

    private func saveAfter(_ delay: TimeInterval) {
        let timer = Timer(timeInterval: max(0, delay), repeats: false) { [weak self] _ in self?.save() }
        // .common so saving continues during scrolling / menu tracking.
        RunLoop.main.add(timer, forMode: .common)
        saveTimer = timer
    }

    private func save() {
        guard isDirty, !isReadOnly else { return }
        let data = Data(textView.string.utf8)
        if let base, base == data {
            markClean()
            return
        }
        do {
            try file.write(data, replacing: base)
            base = data
            markClean()
        } catch {
            report(.error("Couldn't save: \(error.localizedDescription)"))
            saveAfter(2) // keep the edits and retry shortly
        }
    }

    private func markClean() {
        isDirty = false
        dirtySince = nil
        if case .conflict = status { return } // keep the conflict notice visible until the next edit
        report(.saved)
    }

    // MARK: - Disk → editor

    /// Reconcile with whatever is on disk now. Called by the file watcher and on every show.
    func syncFromDisk() {
        switch file.read() {
        case .missing:
            if base != nil {
                base = nil
                report(.missing)
            }
        case .failure(let error):
            report(.error("Can't read file: \(error.localizedDescription)"))
        case .contents(let disk):
            let editor: Data? = isDirty ? Data(textView.string.utf8) : nil
            switch SyncResolver.resolve(base: base, disk: disk, editor: editor) {
            case .none:
                break
            case .adopt:
                base = disk
                markClean()
            case .append(let suffix):
                guard !isReadOnly, let text = String(data: suffix, encoding: .utf8) else {
                    return load(disk)
                }
                textView.appendExternal(text)
                base = disk
                if isDirty { scheduleSave() }
                onExternalChange?()
            case .replace:
                load(disk)
                onExternalChange?()
            case .conflict:
                resolveConflict(disk: disk)
            }
        }
    }

    private func load(_ data: Data) {
        base = data
        isDirty = false
        dirtySince = nil
        if let text = String(data: data, encoding: .utf8) {
            setReadOnly(false)
            textView.replaceAllExternal(text)
            report(.saved)
        } else {
            // Never round-trip a file we can't decode losslessly: that would corrupt it.
            textView.replaceAllExternal(String(decoding: data, as: UTF8.self))
            enterReadOnly("Not valid UTF-8 — read-only")
        }
    }

    /// Unsaved edits here and an incompatible change on disk. Keep ours, back up theirs.
    private func resolveConflict(disk: Data) {
        do {
            let backup = try ConflictBackup.save(disk, originalURL: file.url, in: Settings.conflictsDirectory)
            base = disk
            saveTimer?.invalidate()
            report(.conflict(backup))
            save()
        } catch {
            // Can't back it up: don't overwrite it either. Stop autosaving until resolved.
            saveTimer?.invalidate()
            enterReadOnly("File changed on disk and couldn't be backed up")
        }
    }

    private func enterReadOnly(_ message: String) {
        setReadOnly(true)
        report(.readOnly(message))
    }

    private func setReadOnly(_ readOnly: Bool) {
        isReadOnly = readOnly
        textView.isEditable = !readOnly
    }

    private func report(_ new: NoteStatus) {
        guard new != status else { return }
        status = new
        onStatus?(new)
    }
}
