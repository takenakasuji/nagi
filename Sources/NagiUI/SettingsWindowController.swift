import AppKit
import NagiCore
import SwiftUI

/// Owns the settings window.
///
/// Nagi does not use SwiftUI's `Settings` scene. For an `.accessory` app,
/// clicking a menu bar item never activates the app, and neither `SettingsLink`
/// nor `openSettings()` activates it on our behalf — the window is created and
/// `isVisible`, but stays behind the app the user was actually using, which
/// reads as "nothing happened". Owning the window lets us activate and front it
/// explicitly, the same way `CaptureWindowController` already does.
/// A settings window that can be dismissed from the keyboard.
///
/// Without this it could only be closed by clicking its red button: ⌘W is never
/// dispatched (no File menu exists) and Escape has nowhere to go. The matching
/// rules live in ``SettingsKeyBinding`` as a pure function so they are tested
/// without a window.
final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if SettingsKeyBinding.closes(for: event) {
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Escape. Reaches here through the responder chain — while the hotkey
    /// recorder is armed it consumes Escape first, to cancel recording.
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

@MainActor
public final class SettingsWindowController: SettingsWindowPresenting {
    private var window: NSWindow?
    private let env: AppEnvironment

    public init(env: AppEnvironment) {
        self.env = env
    }

    public func show() {
        let window = window ?? makeWindow()
        self.window = window

        if !window.isVisible {
            window.center()
        }

        // Order matters: activate the app first, then front the window, or the
        // window is fronted within an app that is still in the background.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            // Leaving .miniaturizable and .resizable out renders those buttons
            // dimmed, which is what a settings window should look like.
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Nagi 設定"
        window.isReleasedWhenClosed = false
        // A normal level is right here: unlike the capture panel, Settings is
        // not a transient overlay and should not float above other apps.
        window.level = .normal

        let host = NSHostingView(rootView: SettingsView().environment(env))
        // The window cannot be resized, and its content grows when an error or
        // a hint appears (a failed login-item registration, "修飾キーが必要です").
        // Sizing it once at creation clipped those messages; let the window
        // follow its content instead.
        host.sizingOptions = [.preferredContentSize]
        window.contentView = host
        return window
    }
}
