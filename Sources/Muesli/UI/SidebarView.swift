import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var recorder: RecordingController

    @Binding var selectedID: UUID?
    @Binding var showSetup: Bool
    @State private var searchText = ""

    private var filtered: [Meeting] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.meetings }
        return store.meetings.filter { m in
            m.title.lowercased().contains(q)
                || m.notesMD.lowercased().contains(q)
                || m.transcript.contains { $0.text.lowercased().contains(q) }
        }
    }

    private var grouped: [(day: Date, items: [Meeting])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: filtered) { cal.startOfDay(for: $0.createdAt) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!.sorted { $0.createdAt > $1.createdAt }) }
    }

    var body: some View {
        VStack(spacing: 0) {
            startButton
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            List(selection: $selectedID) {
                ForEach(grouped, id: \.day) { group in
                    Section(sectionTitle(group.day)) {
                        ForEach(group.items) { meeting in
                            SidebarRow(meeting: meeting)
                                .tag(meeting.id)
                                .contextMenu {
                                    Button("Mostrar no Finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([store.folder(for: meeting)])
                                    }
                                    Button("Excluir", role: .destructive) {
                                        if selectedID == meeting.id { selectedID = nil }
                                        store.delete(meeting)
                                    }
                                }
                        }
                    }
                }
            }
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search meetings")

            setupFooter
        }
    }

    private var startButton: some View {
        HStack(spacing: 6) {
            Button {
                Task { await recorder.startNewMeeting() }
            } label: {
                Label(recorder.isRecording ? "Gravando…" : "Iniciar reunião", systemImage: "record.circle.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(CoastalTheme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(recorder.isRecording ? AnyShapeStyle(Color.red.opacity(0.78)) : AnyShapeStyle(CoastalTheme.accentGradient), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(recorder.isRecording)

            if !recorder.isRecording {
                Menu {
                    Button("Iniciar (somente microfone, sem áudio do sistema)") {
                        Task { await recorder.startNewMeeting(captureSystemAudio: false) }
                    }
                    Button("Nova anotação vazia (sem gravação)") {
                        let m = store.createMeeting()
                        selectedID = m.id
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 24)
            }
        }
    }

    @ViewBuilder
    private var setupFooter: some View {
        let status = SetupStatus.current(settings: settings)
        if status.hasBlockers || !status.aiReady {
            Divider()
            Button {
                showSetup = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(status.hasBlockers ? "Conclua a configuração para gravar" : "Adicione um provedor de IA para aprimorar")
                        .font(.callout)
                    Spacer()
                }
                .padding(10)
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = cal.component(.year, from: day) == cal.component(.year, from: Date())
            ? "EEEE, MMM d" : "MMM d, yyyy"
        return f.string(from: day)
    }
}

struct SidebarRow: View {
    @EnvironmentObject private var recorder: RecordingController
    let meeting: Meeting

    private var isLive: Bool { recorder.recordingMeetingID == meeting.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                if isLive {
                    Circle().fill(.red).frame(width: 7, height: 7)
                }
                Text(meeting.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(meeting.createdAt, format: .dateTime.hour().minute())
                if meeting.durationSeconds > 0 {
                    Text("·")
                    Text(formatClock(meeting.durationSeconds))
                }
                if meeting.enhancedMD != nil {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(Color.oat)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
