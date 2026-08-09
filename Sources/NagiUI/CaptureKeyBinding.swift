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
/// when focus is inside the body editor (`NagiTextView`) they are not reliably
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
            // ⌘S too: it is the most reflexive keystroke there is in a text
            // editor, and nothing else in this app claims it. Matched by key
            // code as well, because a Japanese IME does not yield "s".
            if keyCode == 1 || chars == "s" {
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

/// Matches the key press that dismisses the settings window.
///
/// SwiftUI's generated main menu for a `MenuBarExtra`-only app has an Edit menu
/// but no File menu, so ⌘W is never dispatched and the window would otherwise be
/// closable only by clicking its red button.
///
/// Escape is handled separately, via `cancelOperation`. Not because it is exempt
/// from the key-equivalent stage — a bare Escape does reach it, measured; see the
/// Escape rule in `CLAUDE.md` — but because the settings window's view tree has no
/// `.cancelAction` button to claim it there, so `performKeyEquivalent` finds no
/// taker and the event carries on to ordinary `keyDown` dispatch. The capture
/// panel *does* have such a button, which is why Escape takes a different route
/// there.
enum SettingsKeyBinding {
    static func closes(for event: NSEvent) -> Bool {
        closes(
            characters: event.charactersIgnoringModifiers,
            keyCode: event.keyCode,
            modifiers: event.modifierFlags
        )
    }

    static func closes(
        characters: String?,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        let mods = modifiers
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .function, .numericPad])

        guard mods == [.command] else { return false }
        // Key code 13 is W; also match the character, and accept neither being
        // the Latin letter when a Japanese IME is active.
        return keyCode == 13 || (characters ?? "").lowercased() == "w"
    }
}
