import AppKit

/// A command the capture window can perform from a key equivalent.
public enum CaptureCommand: Equatable {
    case save
    case stash
    case settings
}

/// Matches key presses to capture-window commands.
///
/// These are handled at the `NSPanel` level rather than with SwiftUI's
/// `.keyboardShortcut`: the shortcuts hang off zero-sized, hidden buttons, and
/// when focus is inside the `TextEditor` (an `NSTextView`) they are not reliably
/// resolved. `performKeyEquivalent(with:)` gets first refusal on the event, which
/// is what we actually want.
///
/// The matching itself is a pure function so the rules — especially "do not steal
/// ordinary editing shortcuts" — can be tested without an event loop.
enum CaptureKeyBinding {
    static func command(for event: NSEvent) -> CaptureCommand? {
        command(
            characters: event.charactersIgnoringModifiers,
            keyCode: event.keyCode,
            modifiers: event.modifierFlags
        )
    }

    static func command(
        characters: String?,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> CaptureCommand? {
        // CapsLock, Fn and the numeric-pad flag ride along on unrelated keys and
        // must not change what a chord means.
        let mods = modifiers
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .function, .numericPad])

        guard mods.contains(.command) else { return nil }

        let chars = (characters ?? "").lowercased()

        if mods == [.command] {
            // Return (36) or keypad Enter (76).
            if keyCode == 36 || keyCode == 76 || chars == "\r" || chars == "\u{3}" {
                return .save
            }
            if keyCode == 43 || chars == "," {
                return .settings
            }
        }

        // Match S by key code as well as character: with a Japanese IME active
        // the character is not necessarily the Latin letter.
        if mods == [.command, .shift], keyCode == 1 || chars == "s" {
            return .stash
        }

        return nil
    }
}
