import AppKit
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

    private static let nameFont = Font.system(size: 13, weight: .medium)
    private static let nameNSFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    /// Every control in the toolbar draws at this size. Stated once because the
    /// bordered and accessory-bar styles do not agree on a default.
    private static let toolbarFont = Font.system(size: 11)
    /// Room the hint needs before it is worth drawing at all, rather than
    /// letting it slide under the edge of the field.
    private static let suffixWidth: CGFloat = 26

    /// Advance width of `text` in the name field's font.
    ///
    /// Measured directly with AppKit rather than through a `GeometryReader` and
    /// a preference: preferences set inside a `background` do not reliably reach
    /// the parent, which left the hint permanently invisible.
    private static func typedWidth(_ text: String) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return (text as NSString).size(withAttributes: [.font: nameNSFont]).width
    }

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

    /// The name field, with the extension that will actually be written shown in
    /// a lighter colour immediately after the typed text.
    ///
    /// This replaces the old "（.md は自動）" placeholder: it states the same rule
    /// at the moment it applies, and it disappears once the name already ends in
    /// `.md` — which is exactly when nothing further gets appended.
    private var filenameField: some View {
        TextField("ファイル名", text: $session.filename)
            .textFieldStyle(.plain)
            .font(Self.nameFont)
            .focused($focusedField, equals: .filename)
            // Enter in the name field jumps to the body rather than saving, so a
            // stray Return never writes a half-written note.
            //
            // It has to go through `ui.focusRequest`, not `focusedField`: nothing
            // in the tree claims `.body` for `@FocusState` any more — the body is
            // an `NSViewRepresentable`, which `@FocusState` does not reach — so
            // writing `.body` there matches no view and focus simply stays put.
            // Measured.
            .onSubmit { ui.focusRequest = .body }
            .overlay(alignment: .leading) { markdownHint }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)
    }

    /// ".md" trailing the typed name, in the field's own coordinate space.
    private var markdownHint: some View {
        GeometryReader { proxy in
            let x = Self.typedWidth(session.filename)
            if let suffix = NoteWriter.markdownSuffix(for: session.filename),
               x > 0, x + Self.suffixWidth <= proxy.size.width {
                Text(suffix)
                    .font(Self.nameFont)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .offset(x: x)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var bodyEditor: some View {
        ZStack(alignment: .topLeading) {
            MarkdownTextView(
                text: $session.body,
                isComposing: $ui.isBodyComposing,
                focusToken: bodyFocusToken
            )

            // Not just `session.body.isEmpty`. A Japanese conversion posts no
            // `textDidChange`, so `body` is still "" while the reading is on
            // screen — and the placeholder would sit directly on top of the first
            // word the user types, same inset, same font. For a window whose
            // primary use is "type the first word into an empty editor", that is
            // the common case, not an edge case.
            if session.body.isEmpty && !ui.isBodyComposing {
                // .secondary rather than .tertiary: tertiary measures ~1.9:1
                // against this background, far below the 4.5:1 minimum.
                // 10 / 8, not 15 / 8: `MarkdownTextView` sets its own
                // `textContainerInset` of (10, 8) and zeroes the text container's
                // line-fragment padding, so the first glyph is at x=10 — the 5pt
                // this used to add belonged to `TextEditor`'s container, which is
                // gone. Measured against the real hosted view, not assumed: with
                // this padding, rendering the body area with the placeholder
                // showing and rendering it with a single typed glyph ("あ") in an
                // otherwise empty editor produce ink bounding boxes whose left and
                // top edges agree to within a device pixel (minX 20 vs. 22, minY
                // 21 vs. 21, at a 2x backing scale — under a point either way).
                Text("雑に書く。整理はあとで Claude に任せる。")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 120)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
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

            if let message = ui.message {
                messageView(message)
            }

            Spacer(minLength: 8)

            // The font goes on the label, not the environment: .borderedProminent
            // substitutes its own font for the control size and ignores an
            // ambient .font(), while .accessoryBar honours it — which is why
            // these two used to render at visibly different sizes.
            Button { env.stash() } label: {
                Text("退避 ⌘⇧S").font(Self.toolbarFont)
            }
            .buttonStyle(.accessoryBar)
            .help("書きかけを退避してエディタを空にする")

            Button { env.save() } label: {
                Text("保存 ⌘↩").font(Self.toolbarFont)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
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
