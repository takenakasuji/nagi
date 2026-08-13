import Foundation
import Observation

/// Transient view state that isn't part of the saved model: which field wants
/// focus, whether the stash list is open, and the current inline message.
///
/// Separate from `DraftSession` so nothing about presentation leaks into the
/// tested core.
@MainActor
@Observable
public final class CaptureUIState {
    public enum Field: Hashable {
        case filename
        case body
    }

    /// A request to move focus. Wrapped with a token so asking for the same
    /// field twice still triggers, and cleared once the view honours it.
    public struct FocusRequest: Equatable {
        public let field: Field
        public let token: UUID

        public static var filename: FocusRequest { FocusRequest(field: .filename, token: UUID()) }
        public static var body: FocusRequest { FocusRequest(field: .body, token: UUID()) }
    }

    public var focusRequest: FocusRequest?
    public var isStashListVisible = false

    /// True while an input method is holding an unconfirmed reading in the body.
    ///
    /// Nothing else can see it: a conversion posts no `textDidChange` (measured),
    /// so `session.body` stays at its pre-conversion value — `""` for the common
    /// case of typing the first word into an empty window — while the reading is
    /// on screen. The placeholder has to be driven from here or it sits on top of
    /// what the user is typing. `NagiTextView.onCompositionChange` reports it.
    ///
    /// It lives here rather than in a `@State` inside `CaptureView` so a test can
    /// assert the reporting actually arrives somewhere, instead of only that a
    /// closure was installed.
    public var isBodyComposing = false

    /// True while an input method is holding an unconfirmed reading in the
    /// filename field.
    ///
    /// The `.md` hint reads this to step aside during a conversion: the hint's
    /// position is measured from the filename *binding*, which the reading never
    /// reaches, so mid-conversion the hint would sit on top of the text being
    /// typed. The field editor is SwiftUI's, so unlike the body there is no
    /// `setMarkedText` override to report from — `CapturePanel` reads the state
    /// as events pass through it (`reportFilenameComposition()`).
    public var isFilenameComposing = false

    /// Short-lived feedback shown under the editor (e.g. "名前を入れてください").
    public var message: Message?

    public struct Message: Equatable {
        public enum Kind { case info, warning }
        public let kind: Kind
        public let text: String
    }

    public func warn(_ text: String) {
        message = Message(kind: .warning, text: text)
    }

    public func inform(_ text: String) {
        message = Message(kind: .info, text: text)
    }

    public func clearMessage() {
        message = nil
    }
}
