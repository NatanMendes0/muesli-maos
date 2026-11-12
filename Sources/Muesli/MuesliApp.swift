import SwiftUI
import AppKit

@main
struct MuesliApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store: MeetingStore
    @StateObject private var settings: AppSettings
    @StateObject private var recorder: RecordingController
    @StateObject private var updateChecker = UpdateChecker()
    @StateObject private var templateStore = TemplateStore.shared
    @State private var selectedMeetingID: UUID?

    init() {
        // Hidden CLI entry points for headless verification (--selftest, --transcribe, etc.).
        if MuesliCLI.runIfNeeded() {
            exit(0)
        }
        let settings = AppSettings()
        let store = MeetingStore(baseDir: settings.baseDir)
        let recorder = RecordingController(store: store, settings: settings)
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: store)
        _recorder = StateObject(wrappedValue: recorder)
        _selectedMeetingID = State(initialValue: store.meetings.first?.id)
    }

    var body: some Scene {
        WindowGroup("Muesli v\(AppVersion.current)") {
            ContentView(selectedMeetingID: $selectedMeetingID)
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(recorder)
                .environmentObject(updateChecker)
                .environmentObject(templateStore)
                .preferredColorScheme(settings.themeMode.colorScheme)
                .frame(minWidth: 960, minHeight: 620)
                .onAppear {
                    updateChecker.checkOnLaunch()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    store.reload()
                }
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nova reunião (gravar)") {
                    Task {
                        await recorder.startNewMeeting()
                        if let id = recorder.recordingMeetingID {
                            selectedMeetingID = id
                        }
                    }
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(recorder.isRecording)

                Button("Parar gravação") {
                    Task { await recorder.stop() }
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!recorder.isRecording)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(store)
                .environmentObject(updateChecker)
                .environmentObject(templateStore)
                .preferredColorScheme(settings.themeMode.colorScheme)
        }

        MenuBarExtra {
            MenuBarMenu(selectedMeetingID: $selectedMeetingID)
                .environmentObject(store)
                .environmentObject(recorder)
        } label: {
            Image(systemName: recorder.isRecording ? "record.circle.fill" : "waveform.circle")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        RecordingController.shared?.emergencyStop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

struct MenuBarMenu: View {
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var recorder: RecordingController
    @Binding var selectedMeetingID: UUID?

    var body: some View {
        if recorder.isRecording {
            Text("Gravando…")
            Button("Parar gravação") {
                Task { await recorder.stop() }
            }
        } else {
            Button("Iniciar gravação") {
                Task {
                    await recorder.startNewMeeting()
                    if let id = recorder.recordingMeetingID { selectedMeetingID = id }
                }
            }
        }
        Divider()
        Button("Abrir Muesli") {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
        }
        Button("Encerrar Muesli") {
            NSApp.terminate(nil)
        }
    }
}
