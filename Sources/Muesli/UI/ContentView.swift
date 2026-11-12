import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var recorder: RecordingController
    @EnvironmentObject private var updateChecker: UpdateChecker
    @Binding var selectedMeetingID: UUID?

    @State private var searchText = ""
    @State private var showSetup = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                SidebarView(
                    selectedMeetingID: $selectedMeetingID,
                    searchText: $searchText,
                    onOpenSetup: { showSetup = true }
                )
                .frame(width: 254)

                Rectangle()
                    .fill(CoastalTheme.separator)
                    .frame(width: 1)

                VStack(spacing: 0) {
                    // Top signature bar (matching Windows .main-topbar)
                    HStack {
                        if let consent = consentNoticeText {
                            Label(consent, systemImage: "info.circle")
                                .font(.caption2)
                                .foregroundStyle(CoastalTheme.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text("Feito por Natan Mendes 🤖")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(CoastalTheme.faintText)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 2)

                    if recorder.isRecording {
                        RecordBar()
                        Rectangle().fill(CoastalTheme.separator).frame(height: 1)
                    }

                    if let warning = recorder.systemAudioWarning ?? recorder.micWarning {
                        WarningBanner(text: warning) {
                            recorder.systemAudioWarning = nil
                            recorder.micWarning = nil
                        }
                    }

                    if let error = recorder.lastError {
                        ErrorBanner(text: error) {
                            recorder.lastError = nil
                        }
                    }

                    if let id = selectedMeetingID, store.meeting(id) != nil {
                        MeetingDetailView(meetingID: id)
                            .id(id)
                    } else {
                        EmptyHomeState(
                            onStart: {
                                Task {
                                    await recorder.startNewMeeting()
                                    if let id = recorder.recordingMeetingID { selectedMeetingID = id }
                                }
                            },
                            onOpenSetup: { showSetup = true }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CoastalTheme.background)
            }
            .background(CoastalTheme.background)

            // Floating top-right update notification (only shown when a newer release exists)
            if let update = updateChecker.availableUpdate, !updateChecker.bannerDismissed {
                UpdateCornerBanner(
                    info: update,
                    onOpenUpdates: {
                        UserDefaults.standard.set("updates", forKey: "settingsSelectedTab")
                        openSettingsWindow()
                    },
                    onDismiss: {
                        updateChecker.bannerDismissed = true
                    }
                )
                .padding(.top, recorder.isRecording ? 72 : 34)
                .padding(.trailing, 18)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Bottom center toast feedback
            if let toast = recorder.toastMessage {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(toast)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(CoastalTheme.btnInkFg)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(CoastalTheme.btnInkBg, in: Capsule())
                            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                        Spacer()
                    }
                    .padding(.bottom, 18)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: recorder.toastMessage)
        .animation(.easeInOut(duration: 0.2), value: updateChecker.availableUpdate != nil)
        .sheet(isPresented: $showSetup) {
            SetupSheet()
                .environmentObject(settings)
                .preferredColorScheme(settings.themeMode.colorScheme)
        }
        .onAppear {
            if SetupStatus.current(settings: settings).hasBlockers {
                showSetup = true
            }
            if selectedMeetingID == nil {
                selectedMeetingID = store.meetings.first?.id
            }
        }
    }

    private var consentNoticeText: String? {
        guard recorder.isRecording, settings.showConsentNotice else { return nil }
        let s = settings.consentSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
}

func openSettingsWindow() {
    if #available(macOS 14.0, *) {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    } else {
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
    NSApp.activate(ignoringOtherApps: true)
}

private struct UpdateCornerBanner: View {
    let info: UpdateReleaseInfo
    let onOpenUpdates: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("🚀").font(.system(size: 16))
            VStack(alignment: .leading, spacing: 1) {
                Text("Nova versão: \(info.latestVersion)")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(CoastalTheme.infoFg)
                Text("Instalada: v\(info.currentVersion)")
                    .font(.system(size: 11))
                    .foregroundStyle(CoastalTheme.secondaryText)
            }
            Button("Atualizar", action: onOpenUpdates)
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(CoastalTheme.infoFg, in: RoundedRectangle(cornerRadius: 6))
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(CoastalTheme.secondaryText)
            }
            .buttonStyle(.plain)
            .help("Dispensar")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(CoastalTheme.infoBg, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(CoastalTheme.infoBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
    }
}

private struct EmptyHomeState: View {
    @EnvironmentObject private var settings: AppSettings
    let onStart: () -> Void
    let onOpenSetup: () -> Void

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Bom dia!" }
        if hour < 18 { return "Boa tarde!" }
        return "Boa noite!"
    }

    var body: some View {
        VStack(spacing: 14) {
            Text("🥣")
                .font(.system(size: 46))
            Text(greeting)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(CoastalTheme.text)
            Text("Inicie uma nova gravação ou selecione uma reunião anterior na barra lateral.\nSeu áudio é transcrito localmente no Mac via Whisper.")
                .font(.system(size: 13.5))
                .foregroundStyle(CoastalTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            HStack(spacing: 10) {
                Button(action: onStart) {
                    Label("Iniciar nova reunião", systemImage: "record.circle")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(CoastalTheme.btnInkFg)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(CoastalTheme.btnInkBg, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)

                if SetupStatus.current(settings: settings).hasBlockers {
                    Button("Verificar setup", action: onOpenSetup)
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CoastalTheme.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(CoastalTheme.surface, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(CoastalTheme.border, lineWidth: 1))
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct WarningBanner: View {
    let text: String
    let dismiss: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(CoastalTheme.warnFg)
            Text(text).font(.caption).foregroundStyle(CoastalTheme.warnFg)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.caption2).foregroundStyle(CoastalTheme.warnFg)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(CoastalTheme.warnBg)
        .overlay(Rectangle().fill(CoastalTheme.warnBorder).frame(height: 1), alignment: .bottom)
    }
}

private struct ErrorBanner: View {
    let text: String
    let dismiss: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(CoastalTheme.danger)
            Text(text).font(.caption).foregroundStyle(CoastalTheme.danger)
                .textSelection(.enabled)
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.caption2).foregroundStyle(CoastalTheme.danger)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(CoastalTheme.dangerSoft)
        .overlay(Rectangle().fill(CoastalTheme.danger.opacity(0.25)).frame(height: 1), alignment: .bottom)
    }
}
