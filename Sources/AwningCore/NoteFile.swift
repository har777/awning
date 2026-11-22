import Foundation

public enum NoteReadResult {
    case contents(Data)
    case missing
    case failure(Error)
}

/// Reads and writes the notes file.
///
/// Writes take one of two paths:
/// - **Append**: when the new content is the old content plus more text (the common case
///   for a scratchpad), only the new bytes are appended in place. The inode is kept, so
///   `tail -f` keeps working and nothing is rewritten.
/// - **Replace**: anything else is written atomically (temp file + rename) to the
///   symlink-resolved path, so a crash can never leave a half-written file and a
///   symlinked `notes.txt` (e.g. into Dropbox/iCloud) stays a symlink.
public final class NoteFile {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// The real file behind `url` (symlinks resolved).
    public var resolvedURL: URL { url.resolvingSymlinksInPath() }

    public func read() -> NoteReadResult {
        let target = resolvedURL
        do {
            return .contents(try Data(contentsOf: target))
        } catch {
            if !FileManager.default.fileExists(atPath: target.path) { return .missing }
            return .failure(error)
        }
    }

    public enum WriteMode: Equatable {
        case appended
        case replaced
    }

    /// Writes `data`. `previous` is what we believe is currently on disk (our last save);
    /// it enables the append fast path, which is only taken if the on-disk size still matches.
    @discardableResult
    public func write(_ data: Data, replacing previous: Data?) throws -> WriteMode {
        let target = resolvedURL
        if let previous, !previous.isEmpty, data.count > previous.count, data.hasPrefix(previous) {
            let suffix = data[(data.startIndex + previous.count)...]
            if Self.append(suffix, expectedSize: previous.count, to: target) {
                return .appended
            }
        }
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
        return .replaced
    }

    private static func append(_ chunk: Data, expectedSize: Int, to url: URL) -> Bool {
        let fd = open(url.path, O_WRONLY | O_APPEND)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, Int(st.st_size) == expectedSize else { return false }
        return chunk.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> Bool in
            guard let base = buf.baseAddress else { return true }
            var offset = 0
            while offset < buf.count {
                let n = Darwin.write(fd, base + offset, buf.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                offset += n
            }
            return true
        }
    }
}

/// Saves the on-disk version of a note that lost a conflict, so nothing is ever discarded.
public enum ConflictBackup {
    public static func save(_ data: Data, originalURL: URL, in directory: URL, date: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stem = originalURL.deletingPathExtension().lastPathComponent
        let ext = originalURL.pathExtension.isEmpty ? "txt" : originalURL.pathExtension
        let name = "\(stem)-external-\(formatter.string(from: date))"
        var url = directory.appendingPathComponent(name).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(name)-\(n)").appendingPathExtension(ext)
            n += 1
        }
        try data.write(to: url, options: .atomic)
        return url
    }
}

extension Data {
    /// Fast byte-prefix check (memcmp, not element-wise iteration).
    public func hasPrefix(_ prefix: Data) -> Bool {
        guard prefix.count <= count else { return false }
        if prefix.isEmpty { return true }
        return withUnsafeBytes { a in
            prefix.withUnsafeBytes { b in
                memcmp(a.baseAddress!, b.baseAddress!, prefix.count) == 0
            }
        }
    }
}
