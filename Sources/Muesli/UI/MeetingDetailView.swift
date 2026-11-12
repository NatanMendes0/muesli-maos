import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MeetingDetailView: View {
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var recorder: RecordingController
    @EnvironmentObject private var templateStore: TemplateStore

    let meetingID: UUID

    private enum LeftTab: String, CaseIterable {
        case notes = "Minhas Notas"
        case enhanced = "Aprimorado (IA)"
        case copilot = "📋 Prompt Copilot (SESI)"
    }

    @State private var tab: LeftTab = .notes
    @State private var titleDraft = ""
    @State private var showTranscriptPane = true
    @State private var showChatDock = true
    @State private var confirmDelete = false
    @FocusState private var titleFocused: Bool

    private var meeting: Meeting? { store.meeting(meetingID) }
    private var isEnhancing: Bool { recorder.enhancingMeetingID == meetingID }
    private var isRecordingThis: Bool { recorder.recordingMeetingID == meetingID }

    var body: some View {
        if let m = meeting {
            VStack(spacing: 0) {
                header(m)
                Rectangle().fill(CoastalTheme.separator).frame(height: 1)

                // Main split: Notes/Enhanced/Copilot on left + Collapsible Transcript on right
                HSplitView {
                    leftPane(m)
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

                    if showTranscriptPane {
                        rightTranscriptPane(m)
                            .frame(minWidth: 260, idealWidth: 340, maxWidth: 480, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom Chat Dock
                Rectangle().fill(CoastalTheme.separator).frame(height: 1)
                AskDockView(meetingID: meetingID, expanded: $showChatDock)
            }
            .background(CoastalTheme.background)
            .onAppear {
                titleDraft = m.title
                tab = (m.enhancedMD != nil && !isRecordingThis) ? .enhanced : .notes
            }
            .onChange(of: m.title) { _, newTitle in
                if !titleFocused { titleDraft = newTitle }
            }
            .onChange(of: m.enhancedMD) { oldVal, newVal in
                if oldVal == nil && newVal != nil && tab == .notes && !isRecordingThis {
                    tab = .enhanced
                }
            }
            .confirmationDialog("Excluir “\(m.title)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Mover para o Lixo", role: .destructive) {
                    store.delete(m)
                    recorder.showToast("Reunião movida para o Lixo")
                }
                Button("Cancelar", role: .cancel) {}
            }
        }
    }

    // MARK: - Header

    private func header(_ m: Meeting) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                TextField("Título da reunião", text: $titleDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(CoastalTheme.text)
                    .focused($titleFocused)
                    .onSubmit { commitTitle() }
                    .onChange(of: titleFocused) { _, focused in
                        if !focused { commitTitle() }
                    }

                HStack(spacing: 8) {
                    Text(formattedDate(m.createdAt))
                    if m.durationSeconds > 1 {
                        Text("· \(formatClock(m.durationSeconds))")
                    }
                    if !m.transcript.isEmpty {
                        Text("· \(m.transcript.count) trechos")
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(CoastalTheme.secondaryText)
            }

            Spacer()

            // Template picker
            Picker("", selection: Binding(
                get: { m.templateID },
                set: { store.updateTemplate(meetingID, templateID: $0) }
            )) {
                ForEach(MeetingTemplate.builtin + templateStore.customTemplates) { tpl in
                    Text(tpl.name).tag(tpl.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 190)

            // Enhance button
            Button {
                Task {
                    await recorder.enhance(meetingID: meetingID, automatic: false)
                    if store.meeting(meetingID)?.enhancedMD != nil {
                        tab = .enhanced
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    if isEnhancing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isEnhancing ? "Aprimorando…" : (m.enhancedMD == nil ? "Aprimorar com IA" : "Reaprimorar"))
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(CoastalTheme.btnInkFg)
                .padding(.horizontal, 12)
                .padding(.vertical, 6.5)
                .background(CoastalTheme.btnInkBg, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .disabled(isEnhancing || (!m.hasTranscript && m.notesMD.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))

            // Toggle Transcript pane
            Button {
                withAnimation(.easeInOut(duration: 0.16)) { showTranscriptPane.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showTranscriptPane ? "sidebar.right" : "sidebar.left")
                    Text(showTranscriptPane ? "Ocultar transcrição" : "Transcrição")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CoastalTheme.text)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(CoastalTheme.surface, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(CoastalTheme.separator, lineWidth: 1))
            }
            .buttonStyle(.plain)

            // More menu
            Menu {
                Button("Retranscrever do áudio") {
                    recorder.retranscribe(meetingID: meetingID)
                    recorder.showToast("Retranscrição iniciada…")
                }
                .disabled(recorder.isRecording)

                Button("Abrir pasta no Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.folder(for: m)])
                }

                Divider()

                Button("Excluir reunião", role: .destructive) {
                    confirmDelete = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CoastalTheme.secondaryText)
                    .frame(width: 28, height: 28)
                    .background(CoastalTheme.surface, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(CoastalTheme.separator, lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(CoastalTheme.background)
    }

    // MARK: - Left Pane (Tabs + Toolbar + Editor/Enhanced/Copilot)

    private func leftPane(_ m: Meeting) -> some View {
        VStack(spacing: 0) {
            // Tabs + Quick Export Toolbar
            HStack(spacing: 6) {
                ForEach(LeftTab.allCases, id: \.self) { t in
                    Button {
                        tab = t
                    } label: {
                        Text(t.rawValue)
                            .font(.system(size: 12.5, weight: tab == t ? .semibold : .medium))
                            .foregroundStyle(tab == t ? CoastalTheme.text : CoastalTheme.secondaryText)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(
                                tab == t ? CoastalTheme.surface : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(tab == t ? CoastalTheme.separator : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                ToolbarMiniButton(title: "Copiar p/ Copilot", tint: CoastalTheme.infoFg) {
                    copyString(Enhancer.buildCopilotPrompt(meeting: m), toast: "Prompt SESI copiado para o Copilot! Cole com ⌘V")
                }
                ToolbarMiniButton(title: "Copiar (Obsidian)") {
                    copyString(Enhancer.buildObsidianMarkdown(meeting: m, includeTranscript: false), toast: "Markdown (Obsidian) copiado!")
                }
                ToolbarMiniButton(title: "Copiar + Transcrição") {
                    copyString(Enhancer.buildObsidianMarkdown(meeting: m, includeTranscript: true), toast: "Notas + transcrição copiadas!")
                }
                ToolbarMiniButton(title: "Exportar .md") {
                    exportMarkdown(m)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(CoastalTheme.surfaceSoft)

            Rectangle().fill(CoastalTheme.separator).frame(height: 1)

            // Pane Body
            Group {
                switch tab {
                case .notes:
                    NotesEditor(meetingID: meetingID)
                case .enhanced:
                    EnhancedNotesView(
                        meetingID: meetingID,
                        enhancing: isEnhancing,
                        onEnhance: {
                            Task { await recorder.enhance(meetingID: meetingID, automatic: false) }
                        },
                        onSwitchToCopilot: { tab = .copilot }
                    )
                case .copilot:
                    CopilotPromptPane(meeting: m) {
                        copyString(Enhancer.buildCopilotPrompt(meeting: m), toast: "Prompt SESI copiado! Cole no Copilot com ⌘V")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CoastalTheme.surface)
        }
    }

    // MARK: - Right Transcript Pane

    private func rightTranscriptPane(_ m: Meeting) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Transcrição")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(CoastalTheme.text)
                Spacer()
                if !recorder.isRecording && !m.transcript.isEmpty {
                    Button("Retranscrever") {
                        recorder.retranscribe(meetingID: meetingID)
                        recorder.showToast("Retranscrição local iniciada…")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(CoastalTheme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(CoastalTheme.surface, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(CoastalTheme.separator, lineWidth: 1))
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { showTranscriptPane = false }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CoastalTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Recolher painel de transcrição")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9.5)
            .background(CoastalTheme.surfaceSoft)

            Rectangle().fill(CoastalTheme.separator).frame(height: 1)

            TranscriptView(meetingID: meetingID)
                .background(CoastalTheme.surface)
        }
        .background(CoastalTheme.surface)
    }

    // MARK: - Helpers

    private func commitTitle() {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let m = meeting, !trimmed.isEmpty, trimmed != m.title else { return }
        store.updateTitle(meetingID, title: trimmed)
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "dd 'de' MMM, HH:mm"
        return f.string(from: date)
    }

    private func copyString(_ text: String, toast: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        recorder.showToast(toast)
    }

    private func exportMarkdown(_ m: Meeting) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let safe = m.title.filter { $0.isLetter || $0.isNumber || " -_".contains($0) }.trimmingCharacters(in: .whitespaces)
        panel.nameFieldStringValue = "\(safe.isEmpty ? "Reuniao" : safe).md"
        if panel.runModal() == .OK, let url = panel.url {
            let md = Enhancer.buildObsidianMarkdown(meeting: m, includeTranscript: true)
            do {
                try md.write(to: url, atomically: true, encoding: .utf8)
                recorder.showToast("Exportado: \(url.lastPathComponent)")
            } catch {
                recorder.lastError = "Falha ao exportar: \(error.localizedDescription)"
            }
        }
    }
}

private struct ToolbarMiniButton: View {
    let title: String
    var tint: Color = CoastalTheme.secondaryText
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)
                .background(CoastalTheme.surface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(CoastalTheme.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct CopilotPromptPane: View {
    let meeting: Meeting
    let onCopy: () -> Void

    var body: some View {
        let prompt = Enhancer.buildCopilotPrompt(meeting: meeting)
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("💡 Sem chave de API configurada?")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CoastalTheme.infoFg)
                Text("O Muesli transcreve todo o áudio localmente no Mac de graça. Clique abaixo para copiar a transcrição já embutida nas instruções da Ata Executiva padrão SESI, depois cole (⌘V) no Microsoft 365 Copilot ou ChatGPT.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(CoastalTheme.infoFg)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CoastalTheme.infoBg, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(CoastalTheme.infoBorder, lineWidth: 1))

            Button(action: onCopy) {
                Label("Copiar Prompt Completo para Copilot", systemImage: "doc.on.doc.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(CoastalTheme.infoFg, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            ScrollView {
                Text(prompt)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(CoastalTheme.bodyText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(CoastalTheme.surfaceSoft, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(CoastalTheme.separator, lineWidth: 1))
        }
        .padding(16)
    }
}
