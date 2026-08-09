import AppKit
import NagiCore
import SwiftUI

/// A panel that can take keyboard focus while the app is a menu-bar accessory.
/// `NSPanel` refuses key status by default, which would make the editor unusable.
final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Invoked before the key equivalent reaches the view hierarchy. Returning
    /// true consumes the event.
    var onCommand: ((CaptureCommand) -> Void)?

    /// Claims ⌘Return / ⌘⇧S / ⌘, before the focused `NSTextView` sees them.
    ///
    /// Escape is deliberately not matched here, but it does pass through: a bare
    /// Escape *is* a key equivalent, so `super` walks the view tree and
    /// `CaptureView`'s hidden `.cancelAction` button consumes it. See the Escape
    /// rule in `CLAUDE.md` — including what that costs during a Japanese
    /// conversion.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let command = CaptureKeyBinding.command(for: event) {
            onCommand?(command)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Owns the capture window: creates it lazily, shows it centred and focused,
/// and hides it without destroying the text.
@MainActor
public final class CaptureWindowController {
    private var panel: CapturePanel?
    private let env: AppEnvironment

    public init(env: AppEnvironment) {
        self.env = env
    }

    public var isVisible: Bool { panel?.isVisible ?? false }

    public func show() {
        let panel = panel ?? makePanel()
        self.panel = panel

        centerOnActiveScreen(panel)

        // An accessory app must activate itself or the panel gets no key events.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        // Land the caret in the body so the user can type immediately; the
        // request carries a fresh token so it re-fires even though the view was
        // never torn down.
        env.ui.focusRequest = .body
    }

    /// Orders the panel out. Persisting the draft is `AppEnvironment`'s job —
    /// this stays a pure window operation.
    public func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> CapturePanel {
        let panel = CapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 440),
            // .titled gives standard rounded corners and a drag region for free;
            // the titlebar itself is hidden below for a clean look.
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.minSize = NSSize(width: 420, height: 260)

        panel.onCommand = { [weak env] command in
            switch command {
            case .save: env?.save()
            case .stash: env?.stash()
            case .settings: env?.showSettings()
            }
        }

        let root = CaptureView(
            session: env.session,
            ui: env.ui,
            onRequestHide: { [weak env] in env?.hideCaptureWindow() }
        )
        .environment(env)

        panel.contentView = NSHostingView(rootView: root)

        return panel
    }

    /// Centres on whichever screen the pointer is on, so the window appears
    /// where the user is looking in a multi-display setup.
    private func centerOnActiveScreen(_ panel: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            panel.center()
            return
        }

        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            // Slightly above centre reads better than dead centre.
            y: visible.midY - size.height / 2 + visible.height * 0.06
        ))
    }
}
