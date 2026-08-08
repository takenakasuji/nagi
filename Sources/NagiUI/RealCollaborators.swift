import AppKit
import NagiCore

/// The production folder picker: a modal `NSOpenPanel`.
///
/// Kept here as a thin adapter so `AppEnvironment` never touches AppKit modals
/// directly and stays testable.
@MainActor
public func runNotesDirectoryPicker(startingAt current: URL?) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.prompt = "選択"
    panel.message = "メモを保存するフォルダを選んでください"
    panel.directoryURL = current

    // An accessory app must activate itself or the panel opens behind.
    NSApp.activate(ignoringOtherApps: true)
    return panel.runModal() == .OK ? panel.url : nil
}

extension CaptureWindowController: CaptureWindowPresenting {}

extension HotkeyManager: GlobalHotkeyRegistering {}

/// Builds the fully wired production environment.
@MainActor
public func makeProductionEnvironment() -> AppEnvironment {
    let preferences = Preferences()
    let env = AppEnvironment(
        preferences: preferences,
        store: .defaultStore(),
        directoryPicker: { [weak preferences] in
            runNotesDirectoryPicker(startingAt: preferences?.notesDirectory)
        }
    )

    let window = CaptureWindowController(env: env)
    let hotkey = HotkeyManager { [weak env] in env?.toggleCaptureWindow() }
    let settings = SettingsWindowController(env: env)
    env.start(window: window, hotkey: hotkey, settings: settings)

    return env
}
