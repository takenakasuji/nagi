import AppKit
import NagiCore
import SwiftUI

/// The capture window's text view.
final class NagiTextView: NSTextView {
    /// Escape, outside an IME conversion.
    ///
    /// **Not currently reached.** This was written on the assumption that a bare
    /// Escape is not a key equivalent and so travels the responder chain. It is:
    /// AppKit runs the key-equivalent stage first and accepts an unmodified
    /// Escape, and `CaptureView`'s hidden `.cancelAction` button consumes it
    /// there — measured, see `CLAUDE.md`. Kept because the guard below is the
    /// only thing in the app that protects a Japanese conversion from Escape, and
    /// removing it would erase the record of what still needs deciding.
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        // While Japanese text is being converted, Escape belongs to the input
        // method — it cancels the conversion, not the note.
        guard !hasMarkedText() else { return }
        onCancel?()
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
        // Overwriting the attributes of marked text cancels the conversion on
        // screen, so an IME in flight is left alone; the commit repaints.
        guard !textView.hasMarkedText(), let storage = textView.textStorage else { return }

        storage.beginEditing()
        storage.setAttributes(MarkdownTheme.bodyAttributes,
                              range: NSRange(location: 0, length: storage.length))
        for span in MarkdownHighlighting.spans(in: textView.string) {
            let range = NSRange(location: span.range.lowerBound, length: span.range.count)
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
    /// Set by `CaptureView` when the body should take focus. The coordinator acts
    /// only on a token it has not honoured yet, so asking twice for the same
    /// field still works.
    var focusToken: UUID?
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NagiTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.onCancel = onCancel

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
        textView.onCancel = onCancel

        // Only write back when the model changed underneath us — saving,
        // stashing, discarding, or restoring a stash. Assigning on every
        // keystroke would throw the caret to the front of the document.
        if textView.string != text {
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
            MarkdownTextViewHighlighting.apply(to: textView)
        }
    }
}
