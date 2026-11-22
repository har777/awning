import Foundation

/// Watches the notes file for changes made by anything else (shell appends, other editors,
/// sync clients). Handles editors that save by replacing the file (rename/delete) and files
/// that don't exist yet (watches the parent directory until the file appears).
final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pendingNotify: DispatchWorkItem?
    private var pendingRearm: DispatchWorkItem?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    deinit { stop() }

    func start() {
        stop()
        arm()
    }

    func stop() {
        pendingNotify?.cancel()
        pendingRearm?.cancel()
        source?.cancel()
        source = nil
    }

    private func arm() {
        let file = url.resolvingSymlinksInPath()
        var watchingDirectory = false
        var fd = open(file.path, O_EVTONLY)
        if fd < 0 {
            // File (or even its folder) is gone: watch the nearest existing ancestor folder.
            watchingDirectory = true
            var dir = file.deletingLastPathComponent()
            while fd < 0 {
                fd = open(dir.path, O_EVTONLY)
                if dir.path == "/" { break }
                dir = dir.deletingLastPathComponent()
            }
        }
        guard fd >= 0 else { return }

        let mask: DispatchSource.FileSystemEvent = watchingDirectory
            ? [.write]
            : [.write, .extend, .delete, .rename, .revoke]
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: .main)
        src.setEventHandler { [weak self, weak src] in
            guard let self, let src else { return }
            if watchingDirectory {
                // Something in the folder changed. Re-arm so we move down to a newly created
                // subfolder, or onto the file itself once it exists.
                self.rearmSoon()
                if FileManager.default.fileExists(atPath: file.path) { self.notifySoon() }
                return
            }
            if !src.data.isDisjoint(with: [.delete, .rename, .revoke]) {
                // File was replaced (atomic save) or removed: follow whatever is at the path now.
                self.rearmSoon()
            }
            self.notifySoon()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func rearmSoon() {
        pendingRearm?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.source?.cancel()
            self.source = nil
            self.arm()
        }
        pendingRearm = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func notifySoon() {
        pendingNotify?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pendingNotify = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }
}
