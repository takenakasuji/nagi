import AppKit
import NagiCore
import NagiUI
import SwiftUI

/// The app entry point. Everything substantive lives in `NagiUI` and `NagiCore`
/// so it can be unit-tested; this file only declares the scenes and hands off.
@main
struct NagiApp: App {
    @State private var env = AppDelegate.environment

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Nagi", systemImage: "wind") {
            // The global hotkey is the primary way in, and it is invisible
            // everywhere else until the user opens Settings. Show it here.
            Button("新規メモ（\(env.hotkeyDisplay)）") { env.newNote() }
            Button("退避した下書き") {
                env.ui.isStashListVisible = true
                env.showCaptureWindow()
            }
            Button("編集中のメモを破棄") { env.discardCurrent() }

            Divider()

            if env.hasNotesDirectory {
                Button("保存先を Finder で開く") { env.revealNotesDirectory() }
            } else {
                Button("保存先フォルダを選ぶ…") { env.chooseNotesDirectory() }
            }
            Button("設定…") { env.showSettings() }
                .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Nagi を終了") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Handles the parts of launch that SwiftUI's lifecycle doesn't cover.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The single wired-up environment, shared with the scenes above.
    @MainActor static let environment = makeProductionEnvironment()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt and braces alongside LSUIElement: no Dock icon, no app switcher.
        NSApp.setActivationPolicy(.accessory)

        // First run has nowhere to save; ask once rather than failing at ⌘Enter.
        let env = AppDelegate.environment
        if !env.hasNotesDirectory {
            env.chooseNotesDirectory()
            // Choosing a folder used to be the whole of first run: the panel
            // closed and nothing else happened, leaving no way to discover the
            // hotkey the app is driven by. Open the window once and name it.
            if env.hasNotesDirectory {
                env.showCaptureWindow()
                env.ui.inform("\(env.hotkeyDisplay) でいつでも呼び出せます")
            }
        }
    }

    /// Don't lose unsaved text if the user quits with the window open.
    func applicationWillTerminate(_ notification: Notification) {
        AppDelegate.environment.hideCaptureWindow()
    }
}
