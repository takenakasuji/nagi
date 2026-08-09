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
            coordinator.report(composing: composing)
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

        context.coordinator.adopt(text, in: textView)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NagiTextView else { return }
        let coordinator = context.coordinator
        coordinator.parent = self

        // Only write back when the model changed underneath us — saving,
        // stashing, discarding, or restoring a stash. Assigning on every
        // keystroke would throw the caret to the front of the document.
        if textView.hasMarkedText() {
            // A conversion is in flight, so `text` is out of date *by design*:
            // `setMarkedText` posts no `textDidChange` (measured), so the reading
            // on screen never reached the binding. Two different situations look
            // identical from `textView.string != text` alone, and they need
            // opposite answers:
            //
            //   (a) the model still holds the last value this coordinator put
            //       there — nothing happened but the conversion. Writing back
            //       would replace the reading with the pre-conversion document
            //       (usually ""), cancelling the conversion; measured, it makes
            //       Japanese input outright impossible.
            //
            //   (b) the model holds something else — ⌘Return, ⌘⇧S or a stash
            //       being opened replaced it while the conversion was in flight
            //       (`CapturePanel.performKeyEquivalent` runs ahead of the
            //       responder chain, so those keys arrive mid-conversion). Not
            //       writing back leaves the just-saved or just-stashed note in
            //       the editor, and committing the conversion adopts it as the
            //       current draft again — one note in two places, and the next
            //       ⌘Return writes a duplicate file.
            //
            // Hence the comparison is against what we last pushed, not against
            // `textView.string`, which is the one thing guaranteed to differ
            // during a conversion.
            if text != coordinator.syncedText {
                coordinator.adopt(text, in: textView)
            }
        } else if textView.string != text {
            coordinator.adopt(text, in: textView)
        }

        if let focusToken, coordinator.honouredFocusToken != focusToken {
            coordinator.honouredFocusToken = focusToken
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        var honouredFocusToken: UUID?

        /// The value of the binding the editor is known to be in sync with: the
        /// last string this coordinator either read out of the text view or wrote
        /// into it.
        ///
        /// It exists for the one case where `textView.string` cannot answer
        /// "did the model change underneath us?" — a conversion in flight, where
        /// the two disagree for a legitimate reason. See `updateNSView`.
        private(set) var syncedText: String

        init(_ parent: MarkdownTextView) {
            self.parent = parent
            self.syncedText = parent.text
        }

        /// Replaces the document with a value that came from the model.
        ///
        /// Any conversion in flight ends here, and it is the assignment inside
        /// `replaceDocument` that ends it: measured, `textView.string = …` clears
        /// the marked state even on a first responder with a live input context,
        /// and posts exactly one `textDidChange` carrying the new string. Neither
        /// of the two obvious ways to be explicit about it survives contact with
        /// a measurement — `unmarkText()` *commits* the reading into the old
        /// document and leaves the following assignment silent, and
        /// `inputContext?.discardMarkedText()` does nothing at all here (measured
        /// on a hosted first responder: `hasMarkedText()` stays true, no
        /// notification), because a test binary has no live input session to
        /// discard. Adding it would be code no test could hold to account, whose
        /// most likely answer on a real machine is the input method calling
        /// `unmarkText()` — the first problem.
        ///
        /// The composing flag is settled *before* the assignment on purpose.
        /// This runs from `updateNSView`, i.e. inside a SwiftUI view update, and
        /// otherwise the `textDidChange` the assignment posts would be what flips
        /// it — a state change made in the middle of the pass that is reading it.
        func adopt(_ text: String, in textView: NSTextView) {
            publish(text: text, composing: false)
            MarkdownTextViewHighlighting.replaceDocument(of: textView, with: text)
        }

        /// Carries `NagiTextView`'s composition signal to the placeholder.
        func report(composing: Bool) {
            guard parent.isComposing != composing else { return }
            parent.isComposing = composing
        }

        /// Moves the editor's state into the bindings, skipping writes that would
        /// not change anything.
        ///
        /// The skipping is not an optimisation: `adopt` runs during a SwiftUI
        /// update pass, and the `textDidChange` it provokes arrives back here. A
        /// write of the value SwiftUI already holds would be a state change made
        /// during a view update for no gain at all.
        private func publish(text: String, composing: Bool) {
            syncedText = text
            if parent.text != text { parent.text = text }
            report(composing: composing)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // Committing a conversion goes through `insertText`, which clears the
            // marked state without calling `unmarkText()` (measured) — so this is
            // the only place that sees the end of *that* route.
            publish(text: textView.string, composing: textView.hasMarkedText())
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
