import XCTest
@testable import QuickNotesCore

final class NoteFileTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("qn-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func inode(_ url: URL) throws -> UInt64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs[.systemFileNumber] as! NSNumber).uint64Value
    }

    func testMissingFile() {
        let file = NoteFile(url: dir.appendingPathComponent("nope.txt"))
        guard case .missing = file.read() else { return XCTFail("expected .missing") }
    }

    func testAppendKeepsInode() throws {
        let url = dir.appendingPathComponent("notes.txt")
        let file = NoteFile(url: url)
        let a = Data("hello".utf8)
        XCTAssertEqual(try file.write(a, replacing: nil), .replaced)
        let before = try inode(url)
        let b = Data("hello world".utf8)
        XCTAssertEqual(try file.write(b, replacing: a), .appended)
        XCTAssertEqual(try inode(url), before, "append must not replace the file")
        XCTAssertEqual(try Data(contentsOf: url), b)
    }

    func testAppendFallsBackWhenDiskChangedUnderneath() throws {
        let url = dir.appendingPathComponent("notes.txt")
        let file = NoteFile(url: url)
        let a = Data("hello".utf8)
        try file.write(a, replacing: nil)
        try Data("hello!!".utf8).write(to: url) // someone else changed it
        let b = Data("hello world".utf8)
        XCTAssertEqual(try file.write(b, replacing: a), .replaced)
        XCTAssertEqual(try Data(contentsOf: url), b)
    }

    func testNonAppendEditReplaces() throws {
        let url = dir.appendingPathComponent("notes.txt")
        let file = NoteFile(url: url)
        let a = Data("hello world".utf8)
        try file.write(a, replacing: nil)
        let b = Data("hello".utf8)
        XCTAssertEqual(try file.write(b, replacing: a), .replaced)
        XCTAssertEqual(try Data(contentsOf: url), b)
    }

    func testSymlinkIsPreserved() throws {
        let real = dir.appendingPathComponent("real.txt")
        let link = dir.appendingPathComponent("link.txt")
        try Data("x".utf8).write(to: real)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let file = NoteFile(url: link)
        try file.write(Data("rewritten".utf8), replacing: Data("x!".utf8))
        let dest = try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
        XCTAssertEqual(dest, real.path, "link must still be a symlink")
        XCTAssertEqual(try String(contentsOf: real, encoding: .utf8), "rewritten")
    }

    func testCreatesParentDirectories() throws {
        let url = dir.appendingPathComponent("a/b/notes.txt")
        try NoteFile(url: url).write(Data("hi".utf8), replacing: nil)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "hi")
    }

    func testConflictBackupNeverOverwrites() throws {
        let original = dir.appendingPathComponent("notes.txt")
        let backups = dir.appendingPathComponent("conflicts")
        let date = Date(timeIntervalSince1970: 0)
        let first = try ConflictBackup.save(Data("1".utf8), originalURL: original, in: backups, date: date)
        let second = try ConflictBackup.save(Data("2".utf8), originalURL: original, in: backups, date: date)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "1")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "2")
    }

    func testDataHasPrefix() {
        XCTAssertTrue(Data("abc".utf8).hasPrefix(Data("ab".utf8)))
        XCTAssertTrue(Data("abc".utf8).hasPrefix(Data()))
        XCTAssertFalse(Data("abc".utf8).hasPrefix(Data("abd".utf8)))
        XCTAssertFalse(Data("ab".utf8).hasPrefix(Data("abc".utf8)))
    }
}

final class SyncResolverTests: XCTestCase {
    let a = Data("a".utf8)
    let ab = Data("ab".utf8)
    let x = Data("x".utf8)

    func testOwnWriteIsIgnored() {
        XCTAssertEqual(SyncResolver.resolve(base: a, disk: a, editor: nil), .none)
        XCTAssertEqual(SyncResolver.resolve(base: a, disk: a, editor: x), .none)
    }

    func testExternalAppendIsMerged() {
        XCTAssertEqual(SyncResolver.resolve(base: a, disk: ab, editor: nil), .append(Data("b".utf8)))
        // Even with unsaved local edits, an append can be merged without loss.
        XCTAssertEqual(SyncResolver.resolve(base: a, disk: ab, editor: x), .append(Data("b".utf8)))
    }

    func testCleanEditorTakesDiskVersion() {
        XCTAssertEqual(SyncResolver.resolve(base: ab, disk: x, editor: nil), .replace)
        XCTAssertEqual(SyncResolver.resolve(base: nil, disk: x, editor: nil), .replace)
        XCTAssertEqual(SyncResolver.resolve(base: ab, disk: Data(), editor: nil), .replace)
    }

    func testDirtyEditorDivergedIsConflict() {
        XCTAssertEqual(SyncResolver.resolve(base: ab, disk: x, editor: a), .conflict)
        XCTAssertEqual(SyncResolver.resolve(base: nil, disk: x, editor: a), .conflict)
    }

    func testIdenticalContentIsAdopted() {
        XCTAssertEqual(SyncResolver.resolve(base: a, disk: x, editor: x), .adopt)
    }

    func testEmptyBaseIsNotTreatedAsAppend() {
        // Missing/empty base + new content must not duplicate text into the editor.
        XCTAssertEqual(SyncResolver.resolve(base: Data(), disk: x, editor: nil), .replace)
    }
}

final class TextOpsTests: XCTestCase {
    func testContinuation() {
        XCTAssertEqual(TextOps.continuation(forLine: "- milk"), .insert("- "))
        XCTAssertEqual(TextOps.continuation(forLine: "    * nested"), .insert("    * "))
        XCTAssertEqual(TextOps.continuation(forLine: "- [x] done"), .insert("- [ ] "))
        XCTAssertEqual(TextOps.continuation(forLine: "  - [ ] todo"), .insert("  - [ ] "))
        XCTAssertEqual(TextOps.continuation(forLine: "9. nine"), .insert("10. "))
        XCTAssertEqual(TextOps.continuation(forLine: "1) one"), .insert("2) "))
        XCTAssertEqual(TextOps.continuation(forLine: "> quote"), .insert("> "))
        XCTAssertEqual(TextOps.continuation(forLine: "- "), .clearLine)
        XCTAssertEqual(TextOps.continuation(forLine: "- [ ] "), .clearLine)
        XCTAssertEqual(TextOps.continuation(forLine: "- [ ]"), .clearLine)
        XCTAssertEqual(TextOps.continuation(forLine: "3. "), .clearLine)
        XCTAssertEqual(TextOps.continuation(forLine: "plain text"), .none)
        XCTAssertEqual(TextOps.continuation(forLine: "--- [2026-01-01 10:00] ---"), .none)
        XCTAssertEqual(TextOps.continuation(forLine: ""), .none)
    }

    func testToggleTask() {
        XCTAssertEqual(TextOps.toggleTask("- [ ] buy"), "- [x] buy")
        XCTAssertEqual(TextOps.toggleTask("- [x] buy"), "- [ ] buy")
        XCTAssertEqual(TextOps.toggleTask("  - [X] buy"), "  - [ ] buy")
        XCTAssertEqual(TextOps.toggleTask("- buy"), "- [ ] buy")
        XCTAssertEqual(TextOps.toggleTask("2. buy"), "2. [ ] buy")
        XCTAssertEqual(TextOps.toggleTask("  buy"), "  - [ ] buy")
        XCTAssertEqual(TextOps.toggleTask(""), "- [ ] ")
    }

    func testToggleTasksBlock() {
        XCTAssertEqual(TextOps.toggleTasks("a\n\nb\n"), "- [ ] a\n\n- [ ] b\n")
        XCTAssertEqual(TextOps.toggleTasks("\n"), "- [ ] \n")
    }

    func testIndentOutdent() {
        XCTAssertEqual(TextOps.indent("a\n\nb\n"), "  a\n\n  b\n")
        XCTAssertEqual(TextOps.outdent("    a\n b\n\tc\nd"), "  a\nb\nc\nd")
    }

    func testTimestampSpacing() {
        let d = Date(timeIntervalSince1970: 0)
        let stamp = TextOps.timestamp(d)
        XCTAssertEqual(TextOps.timestampBlock(date: d, preceding: ""), stamp + "\n")
        XCTAssertEqual(TextOps.timestampBlock(date: d, preceding: "a\n\n"), stamp + "\n")
        XCTAssertEqual(TextOps.timestampBlock(date: d, preceding: "a\n"), "\n" + stamp + "\n")
        XCTAssertEqual(TextOps.timestampBlock(date: d, preceding: "ab"), "\n\n" + stamp + "\n")
    }

    func testStats() {
        XCTAssertEqual(TextOps.stats(of: ""), .init(words: 0, lines: 0))
        XCTAssertEqual(TextOps.stats(of: "one"), .init(words: 1, lines: 1))
        XCTAssertEqual(TextOps.stats(of: "one two\nthree\n"), .init(words: 3, lines: 2))
        XCTAssertEqual(TextOps.stats(of: "  a  \n\n b"), .init(words: 2, lines: 3))
        let big = String(repeating: "word ", count: 20_000) as NSString
        XCTAssertEqual(TextOps.stats(of: big).words, 20_000)
    }
}
