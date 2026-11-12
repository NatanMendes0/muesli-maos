import SwiftUI
import AppKit

struct SidebarView: View {
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var recorder: RecordingController
    @Binding var selectedMeetingID: UUID?
    @Binding var searchText: String
    let onOpenSetup: () -> Void

    @State private var confirmDelete: Meeting?

    var body: some View {
        VStack(spacing: 0) {
            // Logo + version badge (matching Windows sidebar)
            HStack(spacing: 7) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(CoastalTheme.text)
                Text("Muesli")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(CoastalTheme.text)
                Text("v\(AppVersion.current)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(CoastalTheme.badgeFg)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(CoastalTheme.badgeBg, in: RoundedRectangle(cornerRadius: 4))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Primary action button + extra modes menu
            HStack(spacing: 6) {
                Button {
                    Task {
                        if recorder.isRecording {
                            await recorder.stop()
                        } else {
                            await recorder.startNewMeeting()
                            if let id = recorder.recordingMeetingID { selectedMeetingID = id }
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(recorder.isRecording ? Color.white : CoastalTheme.btnInkFg)
                            .frame(width: 7, height: 7)
                        Text(recorder.isRecording ? "Parar gravação" : "+ Nova reunião")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(recorder.isRecording ? .white : CoastalTheme.btnInkFg)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        recorder.isRecording ? CoastalTheme.danger : CoastalTheme.btnInkBg,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
                .buttonStyle(.plain)

                if !recorder.isRecording {
                    Menu {
                        Button("Gravar somente microfone") {
                            Task {
                                await recorder.startNewMeeting(captureSystemAudio: false)
                                if let id = recorder.recordingMeetingID { selectedMeetingID = id }
                            }
                        }
                        Button("Nova nota sem áudio") {
                            let m = store.createMeeting()
                            selectedMeetingID = m.id
                        }
                        Divider()
                        Button("Verificar configuração…", action: onOpenSetup)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CoastalTheme.secondaryText)
                            .frame(width: 30, height: 32)
                            .background(CoastalTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(CoastalTheme.separator, lineWidth: 1))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            // Search box
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(CoastalTheme.faintText)
                TextField("Buscar reuniões…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(CoastalTheme.text)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(CoastalTheme.faintText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(CoastalTheme.surface, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(CoastalTheme.separator, lineWidth: 1))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            // Meeting list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if groupedMeetings.isEmpty {
                        Text(searchText.isEmpty ? "Nenhuma reunião ainda." : "Sem resultados.")
                            .font(.caption)
                            .foregroundStyle(CoastalTheme.faintText)
                            .padding(.horizontal, 14)
                            .padding(.top, 20)
                    } else {
                        ForEach(groupedMeetings, id: \.0) { section, items in
                            Text(section)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(CoastalTheme.faintText)
                                .textCase(.uppercase)
                                .padding(.horizontal, 14)
                                .padding(.top, 10)
                                .padding(.bottom, 3)

                            ForEach(items) { m in
                                SidebarRow(
                                    meeting: m,
                                    isSelected: selectedMeetingID == m.id,
                                    isRecording: recorder.recordingMeetingID == m.id
                                ) {
                                    selectedMeetingID = m.id
                                }
                                .contextMenu {
                                    Button("Abrir pasta no Finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([store.folder(for: m)])
                                    }
                                    Divider()
                                    Button("Excluir reunião", role: .destructive) {
                                        confirmDelete = m
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 12)
            }

            Rectangle().fill(CoastalTheme.separator).frame(height: 1)

            // Footer: status + settings + quick theme toggle + quit
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(settings.hasAIConfigured ? CoastalTheme.ok : CoastalTheme.faintText)
                        .frame(width: 7, height: 7)
                    Text(settings.activeProviderSummary)
                        .font(.system(size: 11))
                        .foregroundStyle(CoastalTheme.secondaryText)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 2)

                HStack(spacing: 6) {
                    Button {
                        openSettingsWindow()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "gearshape")
                            Text("Configurações")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CoastalTheme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(CoastalTheme.surface, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(CoastalTheme.separator, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button {
                        let next: AppThemeMode = (settings.themeMode == .dark) ? .light : .dark
                        settings.themeMode = next
                        recorder.showToast(next == .dark ? "Tema escuro ativado" : "Tema claro ativado", duration: 1.8)
                    } label: {
                        Text("🌓")
                            .font(.system(size: 12))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5.5)
                            .background(CoastalTheme.surface, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(CoastalTheme.separator, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Alternar tema claro/escuro")

                    Button {
                        NSApp.terminate(nil)
                    } label: {
                        Image(systemName: "power")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(CoastalTheme.danger)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6.5)
                            .background(CoastalTheme.surface, in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(CoastalTheme.separator, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Encerrar o Muesli completamente")
                }
            }
            .padding(10)
            .background(CoastalTheme.surfaceSoft)
        }
        .background(CoastalTheme.surfaceSoft)
        .confirmationDialog(
            "Excluir “\(confirmDelete?.title ?? "")”?",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Mover para o Lixo", role: .destructive) {
                if let target = confirmDelete {
                    if selectedMeetingID == target.id { selectedMeetingID = nil }
                    store.delete(target)
                    if selectedMeetingID == nil { selectedMeetingID = store.meetings.first?.id }
                    recorder.showToast("Reunião movida para o Lixo")
                }
            }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private var filtered: [Meeting] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.meetings }
        return store.meetings.filter { m in
            m.title.lowercased().contains(q)
                || m.notesMD.lowercased().contains(q)
                || (m.enhancedMD?.lowercased().contains(q) ?? false)
                || m.transcript.contains { $0.text.lowercased().contains(q) }
        }
    }

    private var groupedMeetings: [(String, [Meeting])] {
        let cal = Calendar.current
        var buckets: [(String, [Meeting])] = []
        var index: [String: Int] = [:]
        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "pt_BR")
        monthFormatter.dateFormat = "MMMM 'de' yyyy"

        for m in filtered {
            let label: String
            if cal.isDateInToday(m.createdAt) {
                label = "Hoje"
            } else if cal.isDateInYesterday(m.createdAt) {
                label = "Ontem"
            } else if let weekAgo = cal.date(byAdding: .day, value: -7, to: Date()), m.createdAt > weekAgo {
                label = "Esta semana"
            } else {
                label = monthFormatter.string(from: m.createdAt).capitalized
            }
            if let i = index[label] {
                buckets[i].1.append(m)
            } else {
                index[label] = buckets.count
                buckets.append((label, [m]))
            }
        }
        return buckets
    }
}

private struct SidebarRow: View {
    let meeting: Meeting
    let isSelected: Bool
    let isRecording: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                if isRecording {
                    Circle().fill(CoastalTheme.danger).frame(width: 7, height: 7)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(CoastalTheme.text)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(timeLabel)
                        if meeting.durationSeconds > 5 {
                            Text("· \(formatClock(meeting.durationSeconds))")
                        }
                        if meeting.enhancedMD != nil {
                            Text("· ✨")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(CoastalTheme.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                isSelected ? CoastalTheme.surface : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? CoastalTheme.separator : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private var timeLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = Calendar.current.isDateInToday(meeting.createdAt) ? "HH:mm" : "dd/MM HH:mm"
        return f.string(from: meeting.createdAt)
    }
}
