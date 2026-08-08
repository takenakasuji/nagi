import Foundation
import NagiCore

/// The capture window, as `AppEnvironment` needs it.
///
/// A protocol so the orchestration can be tested without a real `NSPanel` and
/// without an event loop.
@MainActor
public protocol CaptureWindowPresenting: AnyObject {
    var isVisible: Bool { get }
    func show()
    func hide()
}

/// The settings window.
///
/// Nagi owns this window rather than relying on SwiftUI's `Settings` scene:
/// an `.accessory` app is never activated by a menu bar click, and SwiftUI's
/// presentation does not activate it either, so the window would open unseen
/// behind whatever the user was using.
@MainActor
public protocol SettingsWindowPresenting: AnyObject {
    func show()
}

/// Registration of the system-wide hotkey.
@MainActor
public protocol GlobalHotkeyRegistering: AnyObject {
    /// - Returns: `false` when the combination is unavailable (already taken).
    @discardableResult
    func register(_ hotkey: Hotkey) -> Bool
}

/// Asks the user for a folder. Returns `nil` if they cancel.
///
/// Injected because the real implementation runs a modal `NSOpenPanel`, which
/// would block a test run.
public typealias DirectoryPicker = @MainActor () -> URL?
