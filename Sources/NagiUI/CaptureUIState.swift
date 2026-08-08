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
