import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var recorder: RecordingController

    @State private var selectedID: UUID?
    @State private var showSetup = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedID: $selectedID, showSetup: $showSetup)
                .navigationSplitViewColumnWidth(min: 252, ideal: 292, max: 360)
                .background(CoastalTheme.surface)
        } detail: {
            if let meeting = store.meeting(selectedID) {
                MeetingDetailView(meetingID: meeting.id)
                    .id(meeting.id)
            } else {
                EmptyDetailView()
            }
        }
        .background(CoastalTheme.background)
        .tint(CoastalTheme.accentBright)
        .foregroundStyle(CoastalTheme.text)
        .onAppear {
            selectedID = store.meetings.first?.id
            if SetupStatus.current(settings: settings).hasBlockers {
                showSetup = true
            }
        }
        .onChange(of: recorder.recordingMeetingID) { _, newValue in
            if let newValue { selectedID = newValue }
        }
        .sheet(isPresented: $showSetup) {
            SetupSheet()
                .environmentObject(settings)
        }
        .alert("Muesli", isPresented: Binding(
            get: { recorder.lastError != nil },
            set: { if !$0 { recorder.lastError = nil } }
        )) {
            Button("OK") { recorder.lastError = nil }
        } message: {
            Text(recorder.lastError ?? "")
        }
    }
}

struct EmptyDetailView: View {
    @EnvironmentObject private var recorder: RecordingController

    var body: some View {
        ZStack {
            CoastalTheme.background
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(CoastalTheme.accent.opacity(0.13))
                        .frame(width: 420, height: 420)
                        .blur(radius: 90)
                        .offset(x: 120, y: -170)
                }

            VStack(spacing: 20) {
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(CoastalTheme.accentBright)
                    .frame(width: 88, height: 88)
                    .background(CoastalTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(CoastalTheme.accent.opacity(0.45), lineWidth: 1)
                    }

                VStack(spacing: 8) {
                    Text("Seu espaço de reuniões")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .tracking(-0.5)
                    Text("Grave localmente, capture a conversa e transforme\nanotações rápidas em um registro útil quando quiser.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(CoastalTheme.secondaryText)
                        .lineSpacing(3)
                }

                Button {
                    Task { await recorder.startNewMeeting() }
                } label: {
                    Label("Iniciar uma reunião", systemImage: "record.circle.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(CoastalTheme.text)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(CoastalTheme.accentGradient, in: Capsule())
                        .overlay { Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(44)
            .coastalCard(padding: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
