# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Nagi is a macOS menu-bar quick-capture app: a global hotkey opens a window, you type, and it writes a `.md` file into a folder you choose. Organising, renaming and structuring those notes is deliberately left to Claude Code / Obsidian afterwards — **there is no AI in the app itself**. Keep it that way unless asked; the value is that capture stays instant.

## Commands

```bash
./scripts/test.sh                  # all tests
```

```bash
./scripts/build-app.sh             # release build -> build/Nagi.app
```

Run a single test or suite (any `swift test` flag is forwarded):

```bash
./scripts/test.sh --filter "CaptureKeyBinding"
```

Skip the tests that need a window server (headless / CI):

```bash
./scripts/test.sh --skip "RealAppKit"
```

`--filter` / `--skip` match the **type** name (`RealAppKitIntegrationTests`), not the `@Suite` display name — `--skip "Real AppKit integration"` matches nothing and silently runs everything. There is no tag-based filtering through `swift test`, so the `.gui` tag is documentation only.

Install and restart — always kill the old instance first, or two copies compete for the same bundle identifier and menu bar slot:

```bash
pkill -f "Nagi.app/Contents/MacOS/Nagi"; ./scripts/build-app.sh && rm -rf /Applications/Nagi.app && cp -R build/Nagi.app /Applications/ && open /Applications/Nagi.app
```

### Do not use `swift test` directly

This project is built with plain SwiftPM so it works with **only the Command Line Tools installed** — there is no Xcode project and `xcodebuild`/XcodeGen are not available. `scripts/test.sh` exists because that configuration needs two fixes: it adds the search paths for swift-testing's `Testing.framework`, and it disables cross-import overlays (the CLT ships `_Testing_Foundation`'s dylib but not its `.swiftmodule`, so `import Foundation` + `import Testing` in one file fails to resolve). Both are no-ops under a full Xcode. Use the script.

Likewise `swift build` alone only produces a bare executable. A menu-bar app needs a real bundle — `LSUIElement`, a bundle ID, an ad-hoc signature — which `scripts/build-app.sh` assembles around the binary.

## Architecture

Three targets, side effects pushed to the edge:

| Target | Role |
|---|---|
| `NagiCore` | Pure logic. Must not import AppKit or SwiftUI. |
| `NagiUI` | Views, windows, the global hotkey, and the orchestration between them. A library, not part of the executable, so orchestration is unit-testable. |
| `Nagi` | `@main` and the `AppDelegate` only. |

`DraftSession` (Core) owns the editor's state machine — `save` / `stash` / `suspend` / `openStash` — and every transition persists through `StashStore`. `AppEnvironment` (UI) is the single place a user action becomes a Core transition; it holds `session`, `ui` (transient view state: focus requests, toolbar message, popover visibility) and the injected collaborators.

Collaborators are protocols (`Collaborators.swift`) with real implementations in `RealCollaborators.swift`, wired once by `makeProductionEnvironment()`. Tests substitute stubs, so `AppEnvironment` is tested with no windows and no event loop. **When adding an operation, put the decision in `AppEnvironment` or `DraftSession` and keep the window controllers as dumb adapters** — see the persistence rule below for why.

### Rules that are load-bearing

These encode bugs that were found the hard way. Changing them will reintroduce the bug.

**Draft persistence belongs to `AppEnvironment.hideCaptureWindow()`, not the window controller.** It calls `session.suspend()` before hiding. It used to live in `CaptureWindowController.hide()`, which meant every other hide path silently dropped the user's text. `CaptureWindowController.hide()` is now a pure `orderOut`.

**⌘Return / ⌘⇧S / ⌘, are handled in `CapturePanel.performKeyEquivalent`, not with SwiftUI `.keyboardShortcut`.** Hidden zero-sized buttons carrying `.keyboardShortcut` lose against the focused body editor (`NagiTextView`). The matching rules live in `CaptureKeyBinding` as a pure function and are unit-tested. **Never bind these in both places** — each press would fire twice, and ⌘Return would write two files. Escape is deliberately *not* one of these commands — `performKeyEquivalent` inspects it only to get out of the input method's way; see the Escape rule below for where it actually goes.

**`AppEnvironment.showSettings()` hides the capture panel before showing Settings.** The capture panel is `.floating` (level 3) and the Settings window is level 0; a level-0 window can *never* be ordered above a level-3 one, so `makeKeyAndOrderFront` does not help. Getting the panel out of the way is the fix.

**Nagi owns its Settings window (`SettingsWindowController`) instead of using SwiftUI's `Settings` scene.** For an `.accessory` app, clicking a menu bar item never activates the app, and neither `SettingsLink` nor `openSettings()` calls `NSApp.activate` — the window is created and `isVisible`, but sits behind whatever the user was using, which reads as "nothing happened". Call `NSApp.activate` **synchronously** before fronting: the main dispatch queue is not serviced during menu tracking, so an async hop from a menu action is deferred until the menu closes.

**The hotkey recorder's `NSEvent` local monitor is scoped to the window that armed it.** A local monitor sees every key press in the app, and returning `nil` starves the rest of the app of it — without the guard, arming the recorder and then summoning the capture window leaves it unable to accept a single character.

**Escape is taken by the SwiftUI `.cancelAction` button in `CaptureView`, wherever focus is — except during an IME conversion, which `CapturePanel.performKeyEquivalent` steps aside for.** A bare Escape *is* a key equivalent: AppKit runs the key-equivalent stage before the responder chain and accepts an unmodified Escape exactly as it accepts ⌘Return (`素の Escape も key equivalent の段に流れる` measures this through a main-menu item, which needs no key window). Normally `performKeyEquivalent` passes it to `super`, the walk reaches the hidden button, it returns true, and the event stops there — so Escape hides the window from the body too, and the responder chain never sees it. The button cannot see marked text, though, and a Japanese conversion is cancelled with Escape, so `performKeyEquivalent` returns `false` **without calling `super`** while the first responder `hasMarkedText()`. Both halves are load-bearing: not calling `super` is what keeps the button away from the event, and returning `false` is what lets AppKit continue to ordinary `keyDown` dispatch, where `interpretKeyEvents` hands Escape to the input method. The check is on `firstResponder as? NSTextInputClient` rather than `NSTextView` because `NSTextInputClient` is the protocol that declares `hasMarkedText()` — the guard does not depend on SwiftUI's filename field editor (`_SystemTextFieldFieldEditor`) continuing to be an `NSTextView` under the hood, only on it still doing IME composition, which covers the body's `NagiTextView` too. Corollary: **`NagiTextView` has no `cancelOperation` override and must not grow one** — the only route that reaches the responder chain is the composing one, and an override there would have to defer to `hasMarkedText()` immediately anyway, so it could never do anything on either route (it was dead code, for two commits). Do not "reconcile" this by asserting the responder chain wins — that was the earliest, wrong version of this rule.

**Driving a key event in a test means `performKeyEquivalent` first, then `sendEvent` — not `sendEvent` alone.** `NSWindow.sendEvent` goes to the first responder immediately and only falls back to key equivalents if the chain declines, so it silently skips the stage where ⌘Return and Escape are actually decided. `NSApp.sendEvent` is no substitute: its window half needs a key window, and a `swift test` binary cannot have one. Use the `dispatch(_:through:)` helper in `RealAppKitIntegrationTests`.

**The body editor is `NSTextView`, not `TextEditor`.** Colouring and Return/Tab handling are both impossible through `TextEditor` on macOS 14, and reaching into SwiftUI's own text view breaks the binding it owns. The decisions live in `NagiCore` (`MarkdownHighlighting`, `MarkdownLineEditing`) as pure functions over UTF-16 offsets; `MarkdownTextView` only applies what they return. Keep new rules on the Core side.

**Focus for the body goes through `ui.focusRequest`, never `@FocusState`.** The body is an `NSViewRepresentable`, so no view in the tree claims `.body` for `@FocusState`; writing `focusedField = .body` matches nothing and focus silently stays where it was — which is exactly how Return in the filename field stopped working for two commits. `CaptureView.onChange(of: ui.focusRequest)` turns a `.body` request into a token the representable makes first responder with. The filename field is a real SwiftUI `TextField` and *is* reachable by `@FocusState`; only the body is not.

**`MarkdownLineEditing.indent` returns `ListIndent`, not `TextEdit?`, because "nothing happens" has two meanings.** `notAList` must fall through — `NSTextView`'s default inserts a tab, which is what `TextEditor` did and what this branch promised to preserve. `nowhereToMove` (the first item of a list, or ⇧Tab at the outermost level) must be **swallowed**: falling through there appends an invisible `\t` to a list line and writes it into the `.md`. Collapsing the two back into one `nil` reintroduces that. Keep the distinction in Core; the coordinator only switches on it.

**A conversion posts no `textDidChange` — measured — and three things depend on it.** `setMarkedText` fires no delegate notification, on the first call, on later ones, or on the empty call an input method makes when the user cancels (`変換中は textDidChange が飛ばない（対照つき）` pins it, with an `insertText` control so the instrument is proven first). Consequences: (1) uncommitted text never reaches `session.body`, so Escape mid-conversion **discards** the reading rather than persisting it — do not write the opposite down again; (2) the placeholder cannot be driven from `session.body.isEmpty` alone or it sits on top of the first Japanese word typed into an empty window, so `NagiTextView.onCompositionChange` reports it instead; (3) that report wakes SwiftUI on every keystroke of a conversion, so **`updateNSView`'s write-back must skip while `hasMarkedText()`** — during a conversion `textView.string` and the binding disagree by design, and replacing the document there cancels the conversion and makes Japanese input impossible. Only the last of these is a live path; the same guard in `MarkdownTextViewHighlighting.apply` is defensive, since nothing reaches it mid-conversion.

### macOS gotchas verified in this project

- **`CGWindowListCopyWindowInfo` cannot see status items.** `NSStatusBarWindow.windowNumber` is 2³², which overflows `CGWindowID` (`UInt32`). A menu-bar item will *never* appear there — do not conclude it is missing. Dump `NSApp.windows` from inside the app instead. More generally: before concluding "X does not exist", prove the instrument can detect X when it *is* present.
- **A missing menu bar icon is usually the notch.** When the menu bar is full on a notched MacBook, the newest item is pushed into the notch (`NSScreen.auxiliaryTopLeftArea.maxX` … `auxiliaryTopRightArea.minX`) and macOS draws nothing there and gives no overflow indicator. Not a bug. README has the workarounds.
- **Hotkey conflicts with third-party apps are undetectable.** `RegisterEventHotKey` returns success even when Alfred/Raycast already own the combination. Every hotkey library has this ceiling; surface it to the user rather than trying to defeat it.
- **Activation and z-order cannot be measured while the screen is locked** (`CGSSessionScreenIsLocked`). Known-good paths report `isActive=false`, so readings are meaningless in both directions. Check the lock before trusting such a measurement.
- **`DispatchQueue.main.async` blocks are never run inside `swift test`.** `RunLoop.current.run(until:)` on the main actor does not drain the main queue in the test binary — measured directly with a one-line block that stayed `false`. So anything the app does behind a main-queue hop is invisible to a test, including `MarkdownTextView.updateNSView`'s `makeFirstResponder`. Assert on the request that triggers the hop, not on the first responder, and say why in the test. The control matters: setting `ui.focusRequest = .body` by hand does not move focus in a test either, so a first-responder assertion fails whether the code works or not.
- **`NSTextView.doCommand(by:)` really does route through `textView(_:doCommandBy:)` and then fall through to the default.** Measured — that makes it the right way to test Return/Tab handling end to end, because it can tell "we swallowed the key" from "we declined and AppKit inserted a tab". Calling `coordinator.textView(_:doCommandBy:)` directly cannot: the default never runs, so a wrong `false` looks identical to a correct `true`.

## Testing

Test-first. All 163 tests run in under three seconds and the pure layers are covered thoroughly; the `RealAppKitIntegrationTests` suite exercises the actual `NSPanel`, real `RegisterEventHotKey`, synthesised `NSEvent`s through `performKeyEquivalent`, and real `setMarkedText` conversions, so it needs a window server (29 of the 163 — the other 134 run headless in about 0.03s).

Prefer pushing logic somewhere it can be tested as a pure function — `CaptureKeyBinding` exists precisely so key-equivalent rules could be pinned down without an event loop or a real keystroke. Tests are named in Japanese, matching the UI language.

## UI language

The interface is Japanese. The user-facing term for a parked draft is **退避** — used consistently across the button, the list, toolbar messages and the menu. (Internal code still calls it `stash`.)
