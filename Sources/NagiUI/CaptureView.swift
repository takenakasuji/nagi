import NagiCore
import SwiftUI

/// The capture window's contents: filename on top, body below, a thin toolbar at
/// the bottom, and the stash list as a collapsible panel.
public struct CaptureView: View {
    @Bindable var session: DraftSession
    @Bindable var ui: CaptureUIState
    let onRequestHide: () -> Void

    /// Supplied by the window controller so this view can stay unaware of AppKit.
    @Environment(AppEnvironment.self) private var env

    @FocusState private var focusedField: CaptureUIState.Field?

    /// The body is an `NSViewRepresentable`, which `@FocusState` does not reach.
    /// It gets the request's token instead and makes itself first responder.
    @State private var bodyFocusToken: UUID?

    init(session: DraftSession, ui: CaptureUIState, onRequestHide: @escaping () -> Void) {
        self.session = session
        self.ui = ui
        self.onRequestHide = onRequestHide
    }

    public var body: some View {
        VStack(spacing: 0) {
            filenameField
            Divider()
            bodyEditor
            Divider()
            toolbar
        }
        .background(.regularMaterial)
        .onChange(of: ui.focusRequest) { _, request in
            guard let request else { return }
            switch request.field {
            case .filename:
                focusedField = .filename
            case .body:
                focusedField = nil
                bodyFocusToken = request.token
            }
            ui.focusRequest = nil
        }
        .background(keyboardShortcuts)
    }

    // MARK: - pieces

    private var filenameField: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))

            TextField("ファイル名（.md は自動）", text: $session.filename)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .focused($focusedField, equals: .filename)
                // Enter in the name field jumps to the body rather than saving,
                // so a stray Return never writes a half-written note.
                .onSubmit { focusedField = .body }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var bodyEditor: some View {
        ZStack(alignment: .topLeading) {
            MarkdownTextView(
                text: $session.body,
                focusToken: bodyFocusToken
            )

            if session.body.isEmpty {
                Text("雑に書く。整理はあとで Claude に任せる。")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    // textContainerInset と揃える。lineFragmentPadding は 0 にしてある
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 120)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                ui.isStashListVisible.toggle()
            } label: {
                Label(
                    session.stashes.isEmpty ? "退避" : "退避 \(session.stashes.count)件",
                    systemImage: "tray.full"
                )
                .font(.system(size: 11))
            }
            .buttonStyle(.accessoryBar)
            .help("退避した下書き")
            // A popover keeps the editor at full height — the window is small,
            // and the list is something you glance at, not work in.
            .popover(isPresented: $ui.isStashListVisible, arrowEdge: .top) {
                StashListView(session: session)
                    .frame(width: 340, height: 260)
            }

            Button {
                env.showSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
            }
            .buttonStyle(.accessoryBar)
            .help("設定 ⌘,")

            if let message = ui.message {
                Text(message.text)
                    .font(.system(size: 11))
                    .foregroundStyle(message.kind == .warning ? Color.orange : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button("退避 ⌘⇧S") { env.stash() }
                .buttonStyle(.accessoryBar)
                .font(.system(size: 11))

            Button("保存 ⌘↩") { env.save() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .font(.system(size: 11))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Escape — and it wins wherever focus is, the body included.
    ///
    /// ⌘Return / ⌘⇧S / ⌘, are handled by `CapturePanel.performKeyEquivalent`,
    /// because a hidden zero-sized button does not reliably win the shortcut
    /// against the focused text view. They must NOT also be bound here, or each
    /// press would fire twice — ⌘Return would write two files.
    ///
    /// Escape is different: AppKit accepts an unmodified Escape at the
    /// key-equivalent stage, which runs before the responder chain, so this button
    /// takes it even while the body has focus. Measured. The one exception is an
    /// IME conversion in flight: this button cannot see marked text, so
    /// `CapturePanel.performKeyEquivalent` declines the event before `super` can
    /// walk down here. See the Escape rule in `CLAUDE.md`.
    private var keyboardShortcuts: some View {
        Button("") { onRequestHide() }
            .keyboardShortcut(.cancelAction)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}
