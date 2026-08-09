import AppKit
import NagiCore
import SwiftUI

/// UTF-16 offsets come out of `NagiCore` as `Range<Int>`; the text system wants
/// `NSRange`. One conversion, so the two call sites cannot drift.
extension Range where Bound == Int {
    var nsRange: NSRange { NSRange(location: lowerBound, length: count) }
}

/// The capture window's text view.
///
/// Nearly behaviour-free. It exists so the body editor can be found by type — in
/// `updateNSView`, and in the tests that reach into the hosted view tree — and to
/// report the one thing the text system will not: that an input method is holding
/// text which has not been committed yet.
///
/// In particular it does **not** handle Escape. AppKit runs the key-equivalent
/// stage first: outside an IME conversion the hidden `.cancelAction` button takes
/// a bare Escape there, and only while composing does `CapturePanel` decline it so
/// the event continues to the responder chain — but an override here would still
/// have to defer to `hasMarkedText()` immediately, so it could never do anything.
/// See the Escape rule in `CLAUDE.md`.
final class NagiTextView: NSTextView {
    /// Called with `hasMarkedText()` whenever an input method starts, changes or
    /// abandons a conversion.
    ///
    /// This exists because those transitions are invisible to everything else.
    /// Measured: `setMarkedText` posts **no** `textDidChange` — not on the first
    /// call, not on later ones, and not on the empty call an IME makes when the
    /// user cancels — so the composing text never reaches the binding and
    /// `session.body` stays `""` for the whole conversion. Anything that has to
    /// know the editor is not visually empty (the placeholder) has to be told
    /// from here.
    var onCompositionChange: ((Bool) -> Void)?

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onCompositionChange?(hasMarkedText())
    }

    /// Not the cancel path — measured, `unmarkText()` *commits* the reading into
    /// the document and posts `textDidChange`. It is here so the flag is cleared
    /// on every route out of a conversion, including that one.
    override func unmarkText() {
        super.unmarkText()
        onCompositionChange?(hasMarkedText())
    }
}

/// Applies Markdown colouring to a text view's storage.
///
/// Split out from the coordinator so the colouring can be exercised without
/// building a SwiftUI binding.
@MainActor
enum MarkdownTextViewHighlighting {
    /// Repaints the whole document.
    ///
    /// A capture note is short, and patching only the edited paragraph gets ```
    /// fences wrong the moment one is opened or closed — that state runs past the
    /// edit in both directions. If this ever shows up in a profile, narrow it
    /// then.
    static func apply(to textView: NSTextView) {
        // Belt and braces, not a live path: overwriting the attributes of marked
        // text would cancel the conversion on screen, but nothing actually gets
        // here mid-conversion. `setMarkedText` posts no `textDidChange` (measured),
        // so the coordinator is never woken during one, and `replaceDocument`
        // clears the marked state with its assignment before it calls this. Keep
        // the guard — it costs nothing and the day some new caller does repaint
        // during a conversion is the day it earns its keep.
        guard !textView.hasMarkedText(), let storage = textView.textStorage else { return }

        storage.beginEditing()
        storage.setAttributes(MarkdownTheme.bodyAttributes,
                              range: NSRange(location: 0, length: storage.length))
        for span in MarkdownHighlighting.spans(in: textView.string) {
            let range = span.range.nsRange
            guard NSMaxRange(range) <= storage.length else { continue }
            storage.addAttributes(MarkdownTheme.attributes(for: span.token), range: range)
        }
        storage.endEditing()

        // Otherwise a character typed straight after a code span inherits green.
        textView.typingAttributes = MarkdownTheme.bodyAttributes
    }

    /// Swaps the whole document for one that came from outside the text system —
    /// saving, stashing, discarding, or restoring a stash, all of which leave the
    /// window open.
    ///
    /// Two things have to happen that a bare `textView.string = text` does not do.
    ///
    /// **The undo stack has to go.** Assigning `string` bypasses
    /// `shouldChangeText(in:replacementString:)`, so it neither registers an undo
    /// group nor clears the ones already there — the previous document's groups
    /// would survive into an unrelated buffer. Type a note, ⌘⇧S, then ⌘Z: either
    /// the stashed text is resurrected into the emptied editor (where
    /// `textDidChange` writes it straight back into the session, leaving one draft
    /// in both the stash list and the editor), or the queued undo targets a range
    /// past the end of the new storage and raises `NSRangeException`.
    ///
    /// **A conversion in flight must be ended by the assignment itself — do not
    /// add an explicit `unmarkText()`.** Assigning `string` already clears the
    /// marked-text state, and it posts exactly one `textDidChange` carrying the
    /// *new* string, so the coordinator writes the right value back to the
    /// session. `unmarkText()` does the opposite of what its name suggests: it
    /// *commits* the composition into the old document and posts `textDidChange`
    /// with the stale text, and the following assignment then posts nothing — so
    /// `session.body` would be left holding the abandoned reading while the
    /// editor shows the new document, and the next `updateNSView` would write the
    /// stale text back over it. Measured; see the task 6 report.
    static func replaceDocument(of textView: NSTextView, with text: String) {
        textView.string = text
        textView.undoManager?.removeAllActions()
        apply(to: textView)
    }
}

/// The body editor.
///
/// `TextEditor` cannot colour text on macOS 14 and cannot intercept Return or
/// Tab at all, and reaching into SwiftUI's own text view to add either breaks the
/// binding it owns. Owning the view outright is the only supported path.
struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    /// True while an input method is holding an unconfirmed reading.
    ///
    /// `text` cannot answer this: a conversion posts no `textDidChange`, so the
    /// binding stays `""` from the first keystroke until the user commits, even
    /// though the editor is visibly full of text.
    @Binding var isComposing: Bool
    /// Set by `CaptureView` when the body should take focus. The coordinator acts
    /// only on a token it has not honoured yet, so asking twice for the same
    /// field still works.
    var focusToken: UUID?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NagiTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.onCompositionChange = { [coordinator = context.coordinator] composing in
            coordinator.parent.isComposing = composing
        }

        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = MarkdownTheme.font
        textView.textColor = MarkdownTheme.bodyColor
        textView.typingAttributes = MarkdownTheme.bodyAttributes

        // Every one of these rewrites what the user typed, and this is a file
        // format where "--" and a curly quote are not the same as what was typed.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        textView.textContainerInset = NSSize(width: 10, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        // Spelled out rather than `.greatestFiniteMagnitude`: NSSize takes
        // CGFloat, and the shorthand is ambiguous between CGFloat and Double.
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        MarkdownTextViewHighlighting.replaceDocument(of: textView, with: text)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NagiTextView else { return }
        context.coordinator.parent = self

        // Only write back when the model changed underneath us — saving,
        // stashing, discarding, or restoring a stash. Assigning on every
        // keystroke would throw the caret to the front of the document.
        //
        // The `hasMarkedText()` half is load-bearing, and it is *not* the same
        // defensive guard as the one in `apply`. While an input method is
        // converting, these two disagree by design: the reading is on screen but
        // posts no `textDidChange`, so `text` still holds the document from
        // before the conversion started. Reaching here used to be impossible —
        // nothing woke SwiftUI mid-conversion — but the composing flag that keeps
        // the placeholder off the user's first word now schedules an update on
        // every keystroke of one. Measured without this guard: type かんじ into an
        // empty editor and the next update pass replaces it with "", cancelling
        // the conversion. Japanese input becomes impossible.
        if !textView.hasMarkedText(), textView.string != text {
            MarkdownTextViewHighlighting.replaceDocument(of: textView, with: text)
        }

        if let focusToken, context.coordinator.honouredFocusToken != focusToken {
            context.coordinator.honouredFocusToken = focusToken
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        var honouredFocusToken: UUID?

        init(_ parent: MarkdownTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            // Committing a conversion goes through `insertText`, which clears the
            // marked state without calling `unmarkText()` (measured) — so this is
            // the only place that sees the end of *that* route.
            parent.isComposing = textView.hasMarkedText()
            MarkdownTextViewHighlighting.apply(to: textView)
        }

        /// Return / Tab / ⇧Tab を Core のルールに投げ、`TextEdit` が返れば適用する。
        ///
        /// `false` を返すと `NSTextView` の既定に落ちる。「リスト行以外は今までどおり」
        /// を保つのがこの分岐の役目。
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            // 変換中のキーは入力メソッドのもの。Return は変換の確定に使われる。
            guard !textView.hasMarkedText() else { return false }

            // 選択範囲があるときの Return / Tab は「置き換え」であって
            // リストの操作ではない。既定に任せる。
            let selection = textView.selectedRange()
            guard selection.length == 0 else { return false }

            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                guard let edit = MarkdownLineEditing.newline(in: textView.string,
                                                             caret: selection.location)
                else { return false }
                return apply(edit, to: textView)
            case #selector(NSResponder.insertTab(_:)):
                return applyIndent(outdent: false, to: textView, caret: selection.location)
            case #selector(NSResponder.insertBacktab(_:)):
                return applyIndent(outdent: true, to: textView, caret: selection.location)
            default:
                return false
            }
        }

        /// Tab / ⇧Tab. Core decides; this only carries the answer out.
        ///
        /// `nowhereToMove` must be swallowed. Returning `false` there lets
        /// `NSTextView`'s default run, and its default for Tab is to insert a
        /// literal tab character — so pressing Tab on `- 最初`, the first thing
        /// anyone tries, would silently write an invisible `\t` into the note.
        /// Measured: `doCommand(by: insertTab:)` with a delegate answering `false`
        /// leaves `- 最初\t` behind.
        private func applyIndent(outdent: Bool, to textView: NSTextView, caret: Int) -> Bool {
            switch MarkdownLineEditing.indent(in: textView.string, caret: caret, outdent: outdent) {
            case .notAList:
                return false
            case .nowhereToMove:
                return true
            case .edit(let edit):
                return apply(edit, to: textView)
            }
        }

        /// `shouldChangeText` / `didChangeText` を通す。
        ///
        /// 通さないと編集が undo スタックに乗らず、リストの継続が ⌘Z で取り消せない
        /// ——「勝手に入った記号を消せない」という、いちばん苛立つ壊れ方になる。
        private func apply(_ edit: TextEdit, to textView: NSTextView) -> Bool {
            let range = edit.range.nsRange
            guard textView.shouldChangeText(in: range, replacementString: edit.replacement) else {
                return false
            }
            textView.textStorage?.replaceCharacters(in: range, with: edit.replacement)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: edit.caret, length: 0))
            return true
        }
    }
}
