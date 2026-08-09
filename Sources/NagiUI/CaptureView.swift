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
            focusedField = request.field
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
                // Decorative: the field's own placeholder already names it.
                .accessibilityHidden(true)

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
            TextEditor(text: $session.body)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .focused($focusedField, equals: .body)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            if session.body.isEmpty {
                // .secondary rather than .tertiary: tertiary measures ~1.9:1
                // against this background, far below the 4.5:1 minimum.
                Text("雑に書く。整理はあとで Claude に任せる。")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
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
            // .help() is a tooltip, not a label — VoiceOver needs this.
            .accessibilityLabel("設定")

            if let message = ui.message {
                messageView(message)
            }

            Spacer(minLength: 8)

            Button("退避 ⌘⇧S") { env.stash() }
                .buttonStyle(.accessoryBar)
                .font(.system(size: 11))
                .help("書きかけを退避してエディタを空にする")

            Button("保存 ⌘↩") { env.save() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .font(.system(size: 11))
                .help("保存先フォルダに .md として書き出す（⌘S も可）")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Inline feedback.
    ///
    /// The kind is carried by an icon as well as a colour: orange text measures
    /// ~2.3:1 against a light background, and colour alone is invisible to some
    /// readers. The text itself stays `.primary` so it is always legible, and a
    /// tooltip carries the full string when the toolbar truncates it.
    private func messageView(_ message: CaptureUIState.Message) -> some View {
        HStack(spacing: 4) {
            Image(
                systemName: message.kind == .warning
                    ? "exclamationmark.triangle.fill"
                    : "checkmark.circle.fill"
            )
            .foregroundStyle(message.kind == .warning ? Color.orange : Color.secondary)
            .accessibilityHidden(true)

            Text(message.text)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            // A discarded draft exists nowhere else, so offer the way back.
            if env.canUndoDiscard {
                Button("元に戻す") { env.undoDiscardStash() }
                    .buttonStyle(.link)
            }
        }
        .font(.system(size: 11))
        .help(message.text)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.kind == .warning ? "警告" : "通知"): \(message.text)")
    }

    /// Escape only.
    ///
    /// ⌘Return / ⌘⇧S / ⌘, are handled by `CapturePanel.performKeyEquivalent`,
    /// because a hidden zero-sized button does not reliably win the shortcut
    /// against the focused text view. They must NOT also be bound here, or each
    /// press would fire twice — ⌘Return would write two files.
    private var keyboardShortcuts: some View {
        Button("") { onRequestHide() }
            .keyboardShortcut(.cancelAction)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}
