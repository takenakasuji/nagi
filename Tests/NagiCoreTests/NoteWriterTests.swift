import Foundation
import Testing
@testable import NagiCore

@Suite("NoteWriter")
struct NoteWriterTests {
    /// Creates a unique scratch directory and removes it when `body` returns.
    private func withTempDir<T>(_ body: (URL) throws -> T) throws -> T {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NoteWriterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        return try body(dir)
    }

    // MARK: - writing

    @Test("本文を書き .md 拡張子を補完する")
    func writesBodyAppendingExtension() throws {
        try withTempDir { dir in
            let url = try NoteWriter.write(body: "hello world", filename: "foo", to: dir)

            #expect(url.lastPathComponent == "foo.md")
            #expect(try String(contentsOf: url, encoding: .utf8) == "hello world")
        }
    }

    @Test("既に .md ならば二重に付けない")
    func keepsExistingMarkdownExtension() throws {
        try withTempDir { dir in
            let url = try NoteWriter.write(body: "x", filename: "notes.md", to: dir)
            #expect(url.lastPathComponent == "notes.md")
        }
    }

    @Test("md 以外の拡張子は名前の一部として扱う")
    func treatsOtherExtensionAsPartOfName() throws {
        try withTempDir { dir in
            let url = try NoteWriter.write(body: "x", filename: "report.2026", to: dir)
            #expect(url.lastPathComponent == "report.2026.md")
        }
    }

    // MARK: - collisions

    @Test("同名ファイルがあれば連番を付け、既存を上書きしない")
    func appendsCounterOnCollision() throws {
        try withTempDir { dir in
            let first = try NoteWriter.write(body: "one", filename: "dup", to: dir)
            let second = try NoteWriter.write(body: "two", filename: "dup", to: dir)
            let third = try NoteWriter.write(body: "three", filename: "dup", to: dir)

            #expect(first.lastPathComponent == "dup.md")
            #expect(second.lastPathComponent == "dup-2.md")
            #expect(third.lastPathComponent == "dup-3.md")
            #expect(try String(contentsOf: first, encoding: .utf8) == "one")
            #expect(try String(contentsOf: second, encoding: .utf8) == "two")
        }
    }

    // MARK: - sanitizing

    @Test("パス区切りとコロンを置換し、サブディレクトリを作らない")
    func replacesPathSeparators() throws {
        try withTempDir { dir in
            let url = try NoteWriter.write(body: "x", filename: "a/b:c", to: dir)

            #expect(url.lastPathComponent == "a-b-c.md")
            #expect(url.deletingLastPathComponent().standardizedFileURL.path == dir.standardizedFileURL.path)
        }
    }

    @Test("先頭のドットを落とし隠しファイルにしない")
    func stripsLeadingDots() throws {
        try withTempDir { dir in
            let url = try NoteWriter.write(body: "x", filename: "...hidden", to: dir)
            #expect(url.lastPathComponent == "hidden.md")
        }
    }

    @Test("前後の空白を落とす")
    func trimsWhitespace() throws {
        try withTempDir { dir in
            let url = try NoteWriter.write(body: "x", filename: "  spaced  ", to: dir)
            #expect(url.lastPathComponent == "spaced.md")
        }
    }

    @Test("親ディレクトリへの脱出を許さない")
    func rejectsTraversal() throws {
        try withTempDir { dir in
            let url = try NoteWriter.write(body: "x", filename: "../escape", to: dir)
            #expect(url.deletingLastPathComponent().standardizedFileURL.path == dir.standardizedFileURL.path)
        }
    }

    @Test("改行を含む名前も 1 ファイルに収める")
    func handlesNewlinesInFilename() throws {
        try withTempDir { dir in
            let url = try NoteWriter.write(body: "x", filename: "a\nb", to: dir)
            #expect(url.lastPathComponent == "a-b.md")
        }
    }

    // MARK: - errors

    @Test("ファイル名が空なら emptyFilename を投げる")
    func throwsOnEmptyFilename() throws {
        try withTempDir { dir in
            #expect(throws: NoteWriterError.emptyFilename) {
                try NoteWriter.write(body: "x", filename: "   ", to: dir)
            }
        }
    }

    @Test("サニタイズ後に空になる名前も emptyFilename を投げる")
    func throwsWhenSanitizesToNothing() throws {
        try withTempDir { dir in
            #expect(throws: NoteWriterError.emptyFilename) {
                try NoteWriter.write(body: "x", filename: "///", to: dir)
            }
        }
    }

    @Test("保存先が無ければ作る")
    func createsDestinationDirectory() throws {
        try withTempDir { dir in
            let nested = dir.appendingPathComponent("does/not/exist")
            let url = try NoteWriter.write(body: "x", filename: "n", to: nested)
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }
}
