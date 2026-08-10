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

### Releasing

Bump `CFBundleShortVersionString` in `Resources/Info.plist`, then push a tag of the same number. `.github/workflows/release.yml` tests, builds, zips with `ditto`, and attaches the zip to the GitHub release. A tag that disagrees with the plist fails before the build — the two are duplicated by necessity and the mismatch would otherwise only surface in someone's Downloads folder.

**What is distributed is a universal build (`./scripts/build-app.sh --universal`), and the CI asserts both slices are present.** The runner is Apple Silicon, so the default build ships arm64 only — which the site's "macOS 14 Sonoma 以降" promise does not match, because Sonoma runs on Intel Macs too. `swift build --arch arm64 --arch x86_64` is not the way: SwiftPM hands it to xcbuild, which only exists in a full Xcode, and the CLT-only premise above dies with it. The x86_64 slice is built separately with `-Xswiftc -target` (deployment target read from `Info.plist`, not written twice) and joined with `lipo`. Local builds stay arm64 — the flag is for CI.

**`workflow_dispatch` against an old tag builds that tag's tooling.** `scripts/build-app.sh` lives in the same tree as the source, so pointing the workflow at an old tag gets the old script. This has already bitten once: the pre-`--universal` script took its options as `if [ "${1:-}" = "--debug" ]` and discarded anything else silently, so `--universal` did nothing, the build step *passed*, and an arm64-only bundle came out. The `lipo -archs` check is what caught it. Options are validated now, but the general trap remains — a workflow step that depends on a new script feature is a no-op on tags that predate it.

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

**Inline feedback (`ui.inform` / `ui.warn`) must be set *before* `hideCaptureWindow()`, and `showCaptureWindow()` clears it.** Setting it after the hide meant nothing could ever render the message, and it then survived into the next summon — a fresh, empty note greeting the user with "保存しました: foo.md". `AppEnvironment.beginAction()` is the single place that clears stale feedback (and expires the discard-undo offer).

**The capture panel's close button is routed through `windowShouldClose` to `AppEnvironment.hideCaptureWindow()`, returning `false`.** `.closable` is in the style mask, so without the delegate the red button calls `close()` directly and becomes a second hide path that skips `suspend()` — the exact bug the rule above was written for.

**The hotkey recorder's `NSEvent` local monitor is scoped to the window that armed it.** A local monitor sees every key press in the app, and returning `nil` starves the rest of the app of it — without the guard, arming the recorder and then summoning the capture window leaves it unable to accept a single character.

**Escape is taken by the SwiftUI `.cancelAction` button in `CaptureView`, wherever focus is — except during an IME conversion, which `CapturePanel.performKeyEquivalent` steps aside for.** A bare Escape *is* a key equivalent: AppKit runs the key-equivalent stage before the responder chain and accepts an unmodified Escape exactly as it accepts ⌘Return (`素の Escape も key equivalent の段に流れる` measures this through a main-menu item, which needs no key window). Normally `performKeyEquivalent` passes it to `super`, the walk reaches the hidden button, it returns true, and the event stops there — so Escape hides the window from the body too, and the responder chain never sees it. The button cannot see marked text, though, and a Japanese conversion is cancelled with Escape, so `performKeyEquivalent` returns `false` **without calling `super`** while the first responder `hasMarkedText()`. Both halves are load-bearing: not calling `super` is what keeps the button away from the event, and returning `false` is what lets AppKit continue to ordinary `keyDown` dispatch, where `interpretKeyEvents` hands Escape to the input method. The check is on `firstResponder as? NSTextInputClient` rather than `NSTextView` because `NSTextInputClient` is the protocol that declares `hasMarkedText()` — the guard does not depend on SwiftUI's filename field editor (`_SystemTextFieldFieldEditor`) continuing to be an `NSTextView` under the hood, only on it still doing IME composition, which covers the body's `NagiTextView` too. Corollary: **`NagiTextView` has no `cancelOperation` override and must not grow one** — the only route that reaches the responder chain is the composing one, and an override there would have to defer to `hasMarkedText()` immediately anyway, so it could never do anything on either route (it was dead code, for two commits). Do not "reconcile" this by asserting the responder chain wins — that was the earliest, wrong version of this rule.

**Driving a key event in a test means `performKeyEquivalent` first, then `sendEvent` — not `sendEvent` alone.** `NSWindow.sendEvent` goes to the first responder immediately and only falls back to key equivalents if the chain declines, so it silently skips the stage where ⌘Return and Escape are actually decided. `NSApp.sendEvent` is no substitute: its window half needs a key window, and a `swift test` binary cannot have one. Use the `dispatch(_:through:)` helper in `RealAppKitIntegrationTests`.

**The body editor is `NSTextView`, not `TextEditor`.** Colouring and Return/Tab handling are both impossible through `TextEditor` on macOS 14, and reaching into SwiftUI's own text view breaks the binding it owns. The decisions live in `NagiCore` (`MarkdownHighlighting`, `MarkdownLineEditing`) as pure functions over UTF-16 offsets; `MarkdownTextView` only applies what they return. Keep new rules on the Core side.

**Focus for the body goes through `ui.focusRequest`, never `@FocusState`.** The body is an `NSViewRepresentable`, so no view in the tree claims `.body` for `@FocusState`; writing `focusedField = .body` matches nothing and focus silently stays where it was — which is exactly how Return in the filename field stopped working for two commits. `CaptureView.onChange(of: ui.focusRequest)` turns a `.body` request into a token the representable makes first responder with. The filename field is a real SwiftUI `TextField` and *is* reachable by `@FocusState`; only the body is not.

**`MarkdownLineEditing.indent` returns `ListIndent`, not `TextEdit?`, because "nothing happens" has two meanings.** `notAList` must fall through — `NSTextView`'s default inserts a tab, which is what `TextEditor` did and what this branch promised to preserve. `nowhereToMove` (the first item of a list, or ⇧Tab at the outermost level) must be **swallowed**: falling through there appends an invisible `\t` to a list line and writes it into the `.md`. Collapsing the two back into one `nil` reintroduces that. Keep the distinction in Core; the coordinator only switches on it.

**A conversion posts no `textDidChange` — measured — and three things depend on it.** `setMarkedText` fires no delegate notification, on the first call, on later ones, or on the empty call an input method makes when the user cancels (`変換中は textDidChange が飛ばない（対照つき）` pins it, with an `insertText` control so the instrument is proven first). Consequences: (1) uncommitted text never reaches `session.body`, so Escape mid-conversion **discards** the reading rather than persisting it — do not write the opposite down again; (2) the placeholder cannot be driven from `session.body.isEmpty` alone or it sits on top of the first Japanese word typed into an empty window, so `NagiTextView.onCompositionChange` reports it into `CaptureUIState.isBodyComposing` instead (it lives there, not in a `@State`, so a test can assert the report *arrives* rather than only that a closure was installed); (3) that report wakes SwiftUI on every keystroke of a conversion, so **`updateNSView`'s write-back cannot decide from `textView.string != text` while `hasMarkedText()`** — during a conversion the two disagree by design, and replacing the document there cancels the conversion and makes Japanese input impossible. Only the last of these is a live path; the same guard in `MarkdownTextViewHighlighting.apply` is defensive, since nothing reaches it mid-conversion.

**Skipping the write-back mid-conversion is right only while the binding still holds what the coordinator last put there.** `Coordinator.syncedText` records that value, and `updateNSView` compares against *it*, not against `textView.string` (which is guaranteed to differ during a conversion). A blanket `hasMarkedText()` skip loses data: ⌘⇧S and ⌘Return reach `CapturePanel.performKeyEquivalent` ahead of the responder chain, so they fire mid-conversion; `resetBuffer()` empties `body`, the update pass skips, nothing retries, and committing the conversion writes the *old* document back into the session — the note is then in the stash list and in the editor at once, and the next ⌘Return writes a duplicate file. When the values differ, write back: the `string` assignment inside `replaceDocument` is what ends the conversion (measured). Do not reach for `unmarkText()` (it commits the reading into the old document) or `inputContext?.discardMarkedText()` (measured: does nothing in a test binary — no live input session — so no test could hold it to account, and its likely real-machine answer is the input method calling `unmarkText()`). The pair `空のエディタで変換を始めても、更新で読みが消えない` / `変換中に退避しても、退避した本文がエディタに蘇らない` pins both directions — each fails under the other's fix.

### macOS gotchas verified in this project

- **`CGWindowListCopyWindowInfo` cannot see status items.** `NSStatusBarWindow.windowNumber` is 2³², which overflows `CGWindowID` (`UInt32`). A menu-bar item will *never* appear there — do not conclude it is missing. Dump `NSApp.windows` from inside the app instead. More generally: before concluding "X does not exist", prove the instrument can detect X when it *is* present.
- **A missing menu bar icon is usually the notch.** When the menu bar is full on a notched MacBook, the newest item is pushed into the notch (`NSScreen.auxiliaryTopLeftArea.maxX` … `auxiliaryTopRightArea.minX`) and macOS draws nothing there and gives no overflow indicator. Not a bug. README has the workarounds.
- **Hotkey conflicts with third-party apps are undetectable.** `RegisterEventHotKey` returns success even when Alfred/Raycast already own the combination. Every hotkey library has this ceiling; surface it to the user rather than trying to defeat it.
- **Activation and z-order cannot be measured while the screen is locked** (`CGSSessionScreenIsLocked`). Known-good paths report `isActive=false`, so readings are meaningless in both directions. Check the lock before trusting such a measurement.
- **`DispatchQueue.main.async` blocks are never run inside `swift test`.** `RunLoop.current.run(until:)` on the main actor does not drain the main queue in the test binary — measured directly with a one-line block that stayed `false`. So anything the app does behind a main-queue hop is invisible to a test, including `MarkdownTextView.updateNSView`'s `makeFirstResponder`. Assert on the request that triggers the hop, not on the first responder, and say why in the test. The control matters: setting `ui.focusRequest = .body` by hand does not move focus in a test either, so a first-responder assertion fails whether the code works or not.
- **`NSTextView.doCommand(by:)` really does route through `textView(_:doCommandBy:)` and then fall through to the default.** Measured — that makes it the right way to test Return/Tab handling end to end, because it can tell "we swallowed the key" from "we declined and AppKit inserted a tab". Calling `coordinator.textView(_:doCommandBy:)` directly cannot: the default never runs, so a wrong `false` looks identical to a correct `true`.
- **`NSView.cacheDisplay` cannot render a popover's text while the screen is locked.** Vibrant text blends against a backdrop that is never composited, so `.primary` (and any un-coloured) text comes out blank while `.secondary` still draws — which reads convincingly as "the view is broken". Verified with a popover containing nothing but four `Text`s. `screencapture` returns pure black under the same condition. Confirm the instrument can see known-good text before believing a blank render.
- **SwiftUI installs a full main menu for a `MenuBarExtra`-only `.accessory` app**, including Edit with ⌘Z/⌘X/⌘C/⌘V/⌘A — so copy, paste and undo work in the editor even though no menu bar is displayed (key equivalents still dispatch through `NSApp.mainMenu`). There is no File menu, so **⌘S and ⌘W are never dispatched**; both are handled in `performKeyEquivalent` instead.

## Testing

Test-first. All 190 tests run in under four seconds and the pure layers are covered thoroughly; the `RealAppKitIntegrationTests` suite exercises the actual `NSPanel`, real `RegisterEventHotKey`, synthesised `NSEvent`s through `performKeyEquivalent`, and real `setMarkedText` conversions, so it needs a window server (30 of the 190 — the other 160 run headless in about 0.05s).

Prefer pushing logic somewhere it can be tested as a pure function — `CaptureKeyBinding` exists precisely so key-equivalent rules could be pinned down without an event loop or a real keystroke. Tests are named in Japanese, matching the UI language.

## UI language

The interface is Japanese. The user-facing term for a parked draft is **退避** — used consistently across the button, the list, toolbar messages and the menu. (Internal code still calls it `stash`.)
