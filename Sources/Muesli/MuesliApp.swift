import SwiftUI
import AppKit

@main
enum MuesliMain {
    static func main() {
        if MuesliCLI.runIfNeeded() { return }
        MuesliApp.main()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let controller = RecordingController.shared, controller.isRecording {
            controller.emergencyStop()
        }
        return .terminateNow
    }
}

struct MuesliApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: MeetingStore
    @StateObject private var settings: AppSettings
    @StateObject private var recorder: RecordingController

    init() {
        let store = MeetingStore()
        let settings = AppSettings()
        _store = StateObject(wrappedValue: store)
        _settings = StateObject(wrappedValue: settings)
        _recorder = StateObject(wrappedValue: RecordingController(store: store, settings: settings))
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(recorder)
                .frame(minWidth: 960, minHeight: 620)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nova reunião e gravação") {
                    Task { await RecordingController.shared?.startNewMeeting() }
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Parar gravação") {
                    Task { await RecordingController.shared?.stop() }
                }
                .keyboardShortcut(".", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
        }

        // Keep the status-menu view entirely independent of recorder state.
        // While an NSMenu is tracking, macOS 26 can recurse indefinitely when a
        // SwiftUI MenuBarExtra receives frequent ObservableObject updates (audio
        // levels and the live timer). The menu actions consult the shared
        // controller only when selected, after AppKit has handled the item.
        MenuBarExtra("Muesli", systemImage: "waveform") {
            MenuBarContent()
        }
    }
}

/// A deliberately static menu. Do not observe `RecordingController` here:
/// an NSMenu tracks synchronously and macOS 26 re-enters SwiftUI rendering when
/// an observed recording timer or audio-meter update changes during tracking.
struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Abrir Muesli") {
            openWindow(id: "main")
            DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
        }
        Divider()
        Button("Iniciar nova reunião") {
            Task { await RecordingController.shared?.startNewMeeting() }
        }
        Button("Parar gravação") {
            Task { await RecordingController.shared?.stop() }
        }
        Divider()
        Button("Encerrar Muesli") {
            NSApp.terminate(nil)
        }
    }
}
