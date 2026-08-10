import Foundation

public enum NoteWriterError: Error, Equatable {
    /// The filename was blank, or contained only characters that sanitize away.
    case emptyFilename
}

/// Writes a note body to a `.md` file in a destination folder.
///
/// Stateless by design: everything it needs is passed in, so it is trivially
/// testable and has no notion of app state or preferences.
public enum NoteWriter {
    /// Characters that must never reach the filesystem as part of a filename.
    /// `/` is the path separator; `:` is the legacy HFS separator and is still
    /// shown as `/` by Finder.
    private static let forbidden = CharacterSet(charactersIn: "/:\\")
        .union(.newlines)
        .union(.controlCharacters)

    /// Reduces arbitrary user input to a single safe path component.
    /// Returns `nil` when nothing usable remains.
    static func sanitize(_ raw: String) -> String? {
        // Collapse every forbidden character to "-" so "a/b" reads as "a-b"
        // rather than silently losing the separator.
        let replaced = String(
            String.UnicodeScalarView(
                raw.unicodeScalars.map { forbidden.contains($0) ? "-" : $0 }
            )
        )

        // "..", "." and leading dots would either escape the folder or hide the
        // file, so drop leading dots entirely.
        let trimmed = replaced
            .trimmingCharacters(in: .whitespaces)
            .drop(while: { $0 == "." })

        let name = String(trimmed).trimmingCharacters(in: .whitespaces)

        // If nothing but substituted separators survived (e.g. the user typed
        // "///"), there is no real name here — don't invent "---.md".
        let hasRealCharacter = name.contains { $0 != "-" && $0 != "." && !$0.isWhitespace }
        return hasRealCharacter ? name : nil
    }

    /// Appends `.md` unless the name already ends in it (case-insensitively).
    static func markdownName(_ name: String) -> String {
        name.lowercased().hasSuffix(".md") ? name : name + ".md"
    }

    /// The extension ``write(body:filename:to:)`` would append to `filename`,
    /// or `nil` when it would append nothing — including when the name is one
    /// this writer refuses outright.
    ///
    /// The editor shows this faintly after what the user has typed. Deriving it
    /// from the same rules that name the file is the point: a hint that promised
    /// an extension the writer would not add would be worse than no hint.
    public static func markdownSuffix(for filename: String) -> String? {
        guard let safe = sanitize(filename) else { return nil }
        return markdownName(safe) == safe ? nil : ".md"
    }

    /// Writes `body` as UTF-8 to `<directory>/<filename>.md`.
    ///
    /// Never overwrites: on collision a counter is inserted before the
    /// extension (`dup.md` → `dup-2.md`). Creates `directory` if needed.
    ///
    /// - Returns: the URL actually written.
    @discardableResult
    public static func write(body: String, filename: String, to directory: URL) throws -> URL {
        guard let safe = sanitize(filename) else { throw NoteWriterError.emptyFilename }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let base = markdownName(safe)
        var target = directory.appendingPathComponent(base)

        if FileManager.default.fileExists(atPath: target.path) {
            let stem = (base as NSString).deletingPathExtension
            var counter = 2
            repeat {
                target = directory.appendingPathComponent("\(stem)-\(counter).md")
                counter += 1
            } while FileManager.default.fileExists(atPath: target.path)
        }

        try body.write(to: target, atomically: true, encoding: .utf8)
        return target
    }
}
