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
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Nagi 設定"
        window.isReleasedWhenClosed = false
        // A normal level is right here: unlike the capture panel, Settings is
        // not a transient overlay and should not float above other apps.
        window.level = .normal
        window.contentView = NSHostingView(
            rootView: SettingsView().environment(env)
        )
        window.setContentSize(window.contentView?.fittingSize ?? NSSize(width: 460, height: 320))
        return window
    }
}
