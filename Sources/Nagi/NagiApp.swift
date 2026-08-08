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
            Button("新規メモ") { env.newNote() }
            Button("退避した下書き") {
                env.ui.isStashListVisible = true
                env.showCaptureWindow()
            }

            Divider()

            if !env.hasNotesDirectory {
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
        }
    }

    /// Don't lose unsaved text if the user quits with the window open.
    func applicationWillTerminate(_ notification: Notification) {
        AppDelegate.environment.hideCaptureWindow()
    }
}
