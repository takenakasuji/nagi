import AppKit
import Carbon.HIToolbox
import NagiCore

/// Registers a system-wide hotkey via Carbon's `RegisterEventHotKey`.
///
/// Carbon is used deliberately: it needs no extra dependency and, unlike an
/// `NSEvent` global monitor, requires no Accessibility permission — the user can
/// install Nagi and press the key without visiting System Settings.
@MainActor
public final class HotkeyManager {
    /// Four-char code 'NAGI', identifying our hotkey registrations.
    private static let signature: OSType = 0x4E41_4749

    // Mutated only on the main actor; `deinit` is the sole other reader, and by
    // then no other reference can exist. Marked unsafe so the opaque Carbon
    // pointers can be released from the nonisolated deinit.
    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?
    private nonisolated(unsafe) var handlerRef: EventHandlerRef?

    /// Called on the main actor each time the hotkey is pressed.
    private let onPress: () -> Void

    public init(onPress: @escaping () -> Void) {
        self.onPress = onPress
    }

    deinit {
        // Carbon resources are process-global; release them even if we're torn
        // down. Safe to call off the main actor: these are plain C calls.
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// Points the global hotkey at `hotkey`, replacing any previous binding.
    ///
    /// - Returns: `true` when the key was registered. `false` usually means
    ///   another app already owns that combination.
    @discardableResult
    public func register(_ hotkey: Hotkey) -> Bool {
        unregisterHotKey()
        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.carbonModifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        return true
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    /// Installs the single event handler that receives every hotkey press.
    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // The callback must be a C function pointer, so it cannot capture; the
        // instance travels through userData instead.
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            // Carbon delivers this on the main thread, but hop explicitly so the
            // compiler can prove main-actor isolation.
            MainActor.assumeIsolated { manager.onPress() }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }
}
