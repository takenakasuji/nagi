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

**⌘Return / ⌘⇧S / ⌘, are handled in `CapturePanel.performKeyEquivalent`, not with SwiftUI `.keyboardShortcut`.** Hidden zero-sized buttons carrying `.keyboardShortcut` lose against the focused `TextEditor` (an `NSTextView`). The matching rules live in `CaptureKeyBinding` as a pure function and are unit-tested. **Never bind these in both places** — each press would fire twice, and ⌘Return would write two files. Escape is deliberately *not* in this path: it carries no modifiers and must stay available to the input method for cancelling Japanese conversion, so it reaches `hide()` via `.cancelAction` / the responder chain.

**`AppEnvironment.showSettings()` hides the capture panel before showing Settings.** The capture panel is `.floating` (level 3) and the Settings window is level 0; a level-0 window can *never* be ordered above a level-3 one, so `makeKeyAndOrderFront` does not help. Getting the panel out of the way is the fix.

**Nagi owns its Settings window (`SettingsWindowController`) instead of using SwiftUI's `Settings` scene.** For an `.accessory` app, clicking a menu bar item never activates the app, and neither `SettingsLink` nor `openSettings()` calls `NSApp.activate` — the window is created and `isVisible`, but sits behind whatever the user was using, which reads as "nothing happened". Call `NSApp.activate` **synchronously** before fronting: the main dispatch queue is not serviced during menu tracking, so an async hop from a menu action is deferred until the menu closes.

**Inline feedback (`ui.inform` / `ui.warn`) must be set *before* `hideCaptureWindow()`, and `showCaptureWindow()` clears it.** Setting it after the hide meant nothing could ever render the message, and it then survived into the next summon — a fresh, empty note greeting the user with "保存しました: foo.md". `AppEnvironment.beginAction()` is the single place that clears stale feedback (and expires the discard-undo offer).

**The capture panel's close button is routed through `windowShouldClose` to `AppEnvironment.hideCaptureWindow()`, returning `false`.** `.closable` is in the style mask, so without the delegate the red button calls `close()` directly and becomes a second hide path that skips `suspend()` — the exact bug the rule above was written for.

**The hotkey recorder's `NSEvent` local monitor is scoped to the window that armed it.** A local monitor sees every key press in the app, and returning `nil` starves the rest of the app of it — without the guard, arming the recorder and then summoning the capture window leaves it unable to accept a single character.

### macOS gotchas verified in this project

- **`CGWindowListCopyWindowInfo` cannot see status items.** `NSStatusBarWindow.windowNumber` is 2³², which overflows `CGWindowID` (`UInt32`). A menu-bar item will *never* appear there — do not conclude it is missing. Dump `NSApp.windows` from inside the app instead. More generally: before concluding "X does not exist", prove the instrument can detect X when it *is* present.
- **A missing menu bar icon is usually the notch.** When the menu bar is full on a notched MacBook, the newest item is pushed into the notch (`NSScreen.auxiliaryTopLeftArea.maxX` … `auxiliaryTopRightArea.minX`) and macOS draws nothing there and gives no overflow indicator. Not a bug. README has the workarounds.
- **Hotkey conflicts with third-party apps are undetectable.** `RegisterEventHotKey` returns success even when Alfred/Raycast already own the combination. Every hotkey library has this ceiling; surface it to the user rather than trying to defeat it.
- **Activation and z-order cannot be measured while the screen is locked** (`CGSSessionScreenIsLocked`). Known-good paths report `isActive=false`, so readings are meaningless in both directions. Check the lock before trusting such a measurement.
- **`NSView.cacheDisplay` cannot render a popover's text while the screen is locked.** Vibrant text blends against a backdrop that is never composited, so `.primary` (and any un-coloured) text comes out blank while `.secondary` still draws — which reads convincingly as "the view is broken". Verified with a popover containing nothing but four `Text`s. `screencapture` returns pure black under the same condition. Confirm the instrument can see known-good text before believing a blank render.
- **SwiftUI installs a full main menu for a `MenuBarExtra`-only `.accessory` app**, including Edit with ⌘Z/⌘X/⌘C/⌘V/⌘A — so copy, paste and undo work in the editor even though no menu bar is displayed (key equivalents still dispatch through `NSApp.mainMenu`). There is no File menu, so **⌘S and ⌘W are never dispatched**; both are handled in `performKeyEquivalent` instead.

## Testing

Test-first. All 88 tests run in under a second and the pure layers are covered thoroughly; the `RealAppKitIntegrationTests` suite exercises the actual `NSPanel`, real `RegisterEventHotKey`, and synthesised `NSEvent`s through `performKeyEquivalent`, so it needs a window server (5 of the 88).

Prefer pushing logic somewhere it can be tested as a pure function — `CaptureKeyBinding` exists precisely so key-equivalent rules could be pinned down without an event loop or a real keystroke. Tests are named in Japanese, matching the UI language.

## UI language

The interface is Japanese. The user-facing term for a parked draft is **退避** — used consistently across the button, the list, toolbar messages and the menu. (Internal code still calls it `stash`.)
