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

    /// Reports whether the filename field is holding an uncommitted reading.
    var onFilenameCompositionChange: ((Bool) -> Void)?

    /// Claims ⌘Return / ⌘⇧S / ⌘, before the focused `NSTextView` sees them, and
    /// steps out of Escape's way while an IME conversion is in flight.
    ///
    /// Escape is deliberately not matched as a command, but it does pass through
    /// here: a bare Escape *is* a key equivalent, so `super` walks the view tree
    /// and `CaptureView`'s hidden `.cancelAction` button consumes it — which is how
    /// Escape hides the window from anywhere, the body included.
    ///
    /// The button does not look at marked text, so mid-conversion that same walk
    /// would take a keystroke the user meant for the input method and close the
    /// window with it — and the half-typed reading would be **thrown away**, not
    /// kept: `setMarkedText` posts no `textDidChange` (measured, on a detached
    /// view and on a hosted first-responder one, against a delegate that
    /// demonstrably sees `insertText`), so an uncommitted `かんじ` never reaches
    /// `session.body` and `suspend()` has nothing to persist. Hence the guard:
    /// while the first responder is composing, do **not** call `super` — that is
    /// what keeps the button from seeing the event — and return `false` so AppKit
    /// carries on to ordinary `keyDown` dispatch, where `interpretKeyEvents` hands
    /// Escape to the input method and only the conversion is cancelled. See the
    /// Escape rule in `CLAUDE.md`.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if CaptureKeyBinding.isBareEscape(event), isComposing { return false }

        if let command = CaptureKeyBinding.command(for: event) {
            onCommand?(command)
            reportFilenameComposition()
            return true
        }
        let consumed = super.performKeyEquivalent(with: event)
        if consumed { reportFilenameComposition() }
        return consumed
    }

    /// Every key event passes through here unless the key equivalent stage
    /// consumed it first — `performKeyEquivalent` reports on those paths.
    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)
        switch event.type {
        case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown:
            reportFilenameComposition()
        default:
            break
        }
    }

    /// Publishes whether the filename field is holding an uncommitted reading.
    ///
    /// This exists because the `.md` hint's position is computed from the
    /// filename *binding*, which a conversion never updates — `setMarkedText`
    /// posts no change (measured for the body; the field editor behaves the
    /// same), so the reading sits on screen while the binding still holds the
    /// pre-conversion text, and the hint would overlap it. The body's
    /// `NagiTextView` reports its own conversions by overriding `setMarkedText`;
    /// the filename field cannot — its field editor is SwiftUI's — so the panel
    /// reads the state at the only observation points it has: events passing
    /// through, and `show()`. That is enough because `NSTextInputContext`
    /// handles events synchronously (it answers "consumed?" with a Bool), so by
    /// the time `sendEvent` returns, the marked text is settled.
    ///
    /// The body is excluded by type, not by claiming the first responder must be
    /// a field editor: a conversion in the body must not blink the filename's
    /// hint, whose position is still correct.
    func reportFilenameComposition() {
        let composing = isComposing && !(firstResponder is NagiTextView)
        onFilenameCompositionChange?(composing)
    }

    /// Whether the focused view is holding text an input method has not committed
    /// yet.
    ///
    /// Both editors qualify: the body's `NagiTextView`, and the field editor behind
    /// the filename `TextField` (currently an `NSTextView` of SwiftUI's own, though
    /// that's an implementation detail). `NSTextInputClient` is the protocol that
    /// declares `hasMarkedText()`, so checking it stays correct even if SwiftUI's
    /// field editor changes underneath.
    private var isComposing: Bool {
        (firstResponder as? NSTextInputClient)?.hasMarkedText() ?? false
    }
}

/// Owns the capture window: creates it lazily, shows it centred and focused,
/// and hides it without destroying the text.
@MainActor
public final class CaptureWindowController: NSObject {
    private var panel: CapturePanel?
    private let env: AppEnvironment

    /// Remembers size and position between launches. Without it the panel
    /// invites dragging and resizing (it is movable by its background) and then
    /// throws the result away.
    private static let frameAutosaveName = "NagiCaptureWindow"

    public init(env: AppEnvironment) {
        self.env = env
        super.init()
    }

    public var isVisible: Bool { panel?.isVisible ?? false }

    public func show() {
        let isFirstUse = panel == nil
        let panel = panel ?? makePanel()
        self.panel = panel

        // Only place it ourselves when there is nothing worth restoring, or when
        // the remembered frame is off-screen (an external display went away).
        if isFirstUse, !panel.setFrameUsingName(Self.frameAutosaveName) {
            centerOnActiveScreen(panel)
        } else if !isOnAnyScreen(panel) {
            centerOnActiveScreen(panel)
        }

        // An accessory app must activate itself or the panel gets no key events.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        // The composition flag can be stale here: the panel only reports when an
        // event passes through it, and a conversion that ended while the window
        // was hidden produced no event this panel saw. Re-read reality now, or
        // the `.md` hint stays needlessly hidden until the first keystroke.
        panel.reportFilenameComposition()

        // Land the caret in the body so the user can type immediately; the
        // request carries a fresh token so it re-fires even though the view was
        // never torn down.
        env.ui.focusRequest = .body
    }

    /// Orders the panel out. Persisting the draft is `AppEnvironment`'s job —
    /// this stays a pure window operation.
    public func hide() {
        panel?.saveFrame(usingName: Self.frameAutosaveName)
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

        // The guard is not an optimisation: the panel reports after every key
        // and mouse-down, and an unguarded `@Observable` write would re-render
        // `CaptureView` on each of them.
        panel.onFilenameCompositionChange = { [weak env] composing in
            guard let env, env.ui.isFilenameComposing != composing else { return }
            env.ui.isFilenameComposing = composing
        }

        let root = CaptureView(
            session: env.session,
            ui: env.ui,
            onRequestHide: { [weak env] in env?.hideCaptureWindow() }
        )
        .environment(env)

        panel.contentView = NSHostingView(rootView: root)
        panel.delegate = self

        return panel
    }

    /// True when the panel's remembered frame still intersects a live screen.
    private func isOnAnyScreen(_ panel: NSWindow) -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.intersects(panel.frame) }
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

extension CaptureWindowController: NSWindowDelegate {
    /// The red close button would otherwise call `close()` directly, bypassing
    /// the one path that persists the draft. Route it through the same door as
    /// Escape and the hotkey instead of letting it become a second hide path.
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        env.hideCaptureWindow()
        return false
    }
}
