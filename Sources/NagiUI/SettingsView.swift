import AppKit
import NagiCore
import ServiceManagement
import SwiftUI

public struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env

    public init() {}

    @State private var isRecordingHotkey = false
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    public var body: some View {
        Form {
            Section("保存先") {
                HStack {
                    Text(env.notesDirectoryDisplay)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(env.hasNotesDirectory ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer()
                    Button("変更…") { env.chooseNotesDirectory() }
                }
                Text("⌘Enter でこのフォルダに .md を保存します。Obsidian の Vault や Claude Code の作業フォルダを指定してください。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("ホットキー") {
                HStack {
                    HotkeyRecorder(
                        isRecording: $isRecordingHotkey,
                        display: env.hotkeyDisplay,
                        onCapture: { env.setHotkey($0) }
                    )
                    Spacer()
                    Button("既定に戻す") { env.setHotkey(.defaultHotkey) }
                }
                Text("このキーでメモ入力ウインドウを呼び出します。修飾キーを 1 つ以上含めてください。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("起動") {
                Toggle("ログイン時に起動", isOn: $launchesAtLogin)
                    .onChange(of: launchesAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
                if let loginItemError {
                    Text(loginItemError)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            // Registration fails for an unsigned or non-/Applications build;
            // report it rather than silently flipping the switch back.
            loginItemError = "設定できませんでした: \(error.localizedDescription)"
            launchesAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// Click to arm, then press a combination. Captures the next key-down while
/// armed, using a local monitor so the keystroke never reaches the text system.
private struct HotkeyRecorder: View {
    @Binding var isRecording: Bool
    let display: String
    let onCapture: (Hotkey) -> Void

    @State private var monitor: Any?
    @State private var hint: String?
    /// The window that was key when recording started. Events aimed anywhere
    /// else are left alone — see `startMonitor`.
    @State private var armedWindow: NSWindow?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isRecording.toggle()
            } label: {
                Text(isRecording ? "キーを押してください…" : display)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minWidth: 130)
            }
            .buttonStyle(.bordered)

            if let hint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
        .onChange(of: isRecording) { _, recording in
            if recording { startMonitor() } else { stopMonitor() }
        }
        .onDisappear(perform: stopMonitor)
    }

    private func startMonitor() {
        hint = nil
        armedWindow = NSApp.keyWindow

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // A local monitor sees every key press in the whole app, and
            // swallowing one starves the rest of the app of it. Without this
            // guard, arming the recorder and then summoning the capture window
            // (e.g. by pressing the current hotkey) leaves that window unable to
            // accept a single character — it just looks frozen.
            guard let armedWindow, event.window === armedWindow else {
                isRecording = false
                return event
            }

            // Esc cancels recording without changing the binding.
            if event.keyCode == 53 {
                isRecording = false
                return nil
            }

            let carbon = Self.carbonModifiers(from: event.modifierFlags)
            guard carbon != 0 else {
                hint = "修飾キーが必要です"
                return nil  // swallow, stay armed
            }

            onCapture(Hotkey(keyCode: UInt32(event.keyCode), carbonModifiers: carbon))
            isRecording = false
            return nil
        }
    }

    private func stopMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        armedWindow = nil
        hint = nil
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= Hotkey.cmdKey }
        if flags.contains(.shift) { carbon |= Hotkey.shiftKey }
        if flags.contains(.option) { carbon |= Hotkey.optionKey }
        if flags.contains(.control) { carbon |= Hotkey.controlKey }
        return carbon
    }
}
