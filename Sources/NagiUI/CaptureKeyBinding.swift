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

    /// A bare Escape: key code 53 with nothing but the ignorable flags on it.
    ///
    /// Escape is **not** a `CaptureCommand` and is not handled here — the hidden
    /// `.cancelAction` button in `CaptureView` takes it. `CapturePanel` only has to
    /// recognise it so it can step aside while an IME conversion is in flight; see
    /// the Escape rule in `CLAUDE.md`.
    static func isBareEscape(_ event: NSEvent) -> Bool {
        isBareEscape(keyCode: event.keyCode, modifiers: event.modifierFlags)
    }

    static func isBareEscape(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        keyCode == 53 && significantModifiers(modifiers).isEmpty
    }

    /// CapsLock, Fn and the numeric-pad flag ride along on unrelated keys and must
    /// not change what a chord means.
    private static func significantModifiers(
        _ modifiers: NSEvent.ModifierFlags
    ) -> NSEvent.ModifierFlags {
        modifiers
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .function, .numericPad])
    }

    static func command(
        characters: String?,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> CaptureCommand? {
        let mods = significantModifiers(modifiers)

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
