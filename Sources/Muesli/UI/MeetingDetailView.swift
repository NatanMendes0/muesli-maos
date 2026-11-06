import SwiftUI

enum DetailTab: String, CaseIterable {
    case notes = "Anotações"
    case transcript = "Transcrição"
    case enhanced = "Aprimorada"
    case ask = "Perguntar"

    var icon: String {
        switch self {
        case .notes: return "square.and.pencil"
        case .transcript: return "text.quote"
        case .enhanced: return "sparkles"
        case .ask: return "bubble.left.and.text.bubble.right"
        }
    }
}

struct MeetingDetailView: View {
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var recorder: RecordingController

    let meetingID: UUID
    @State private var tab: DetailTab = .notes
    @State private var titleDraft = ""
    @State private var enhancing = false
    @State private var enhanceError: String?

    private var meeting: Meeting? { store.meeting(meetingID) }
    private var isLive: Bool { recorder.recordingMeetingID == meetingID }

    var body: some View {
        if let meeting {
            VStack(spacing: 0) {
                header(meeting)
                Rectangle()
                    .fill(CoastalTheme.separator)
                    .frame(height: 1)
                if isLive {
                    RecordBar()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(CoastalTheme.surface.opacity(0.7))
                    Rectangle()
                        .fill(CoastalTheme.separator)
                        .frame(height: 1)
                }
                content(meeting)
            }
            .coastalPanel()
            .toolbar { toolbarContent(meeting) }
            .onAppear {
                titleDraft = meeting.title
                if isLive { tab = .notes }
            }
            .onChange(of: meeting.title) { _, new in titleDraft = new }
            .alert("Falha ao aprimorar", isPresented: Binding(
                get: { enhanceError != nil },
                set: { if !$0 { enhanceError = nil } }
            )) {
                Button("OK") { enhanceError = nil }
            } message: {
                Text(enhanceError ?? "")
            }
        } else {
            EmptyDetailView()
        }
    }

    // MARK: - Header

    private func header(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Título da reunião", text: $titleDraft)
                .textFieldStyle(.plain)
                .font(.title.weight(.semibold))
                .onSubmit { store.updateTitle(meetingID, title: titleDraft) }

            HStack(spacing: 8) {
                Text(meeting.createdAt, format: .dateTime.weekday(.wide).month().day().hour().minute())
                if meeting.durationSeconds > 0 {
                    Text("·")
                    Text(formatClock(meeting.durationSeconds))
                }
                Text("·")
                Menu {
                    ForEach(NoteTemplate.all) { t in
                        Button {
                            store.updateTemplate(meetingID, templateID: t.id)
                        } label: {
                            Label(t.name, systemImage: t.icon)
                        }
                    }
                } label: {
                    Label(NoteTemplate.byID(meeting.templateID).name, systemImage: NoteTemplate.byID(meeting.templateID).icon)
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                if let warning = recorder.systemAudioWarning, isLive {
                    Label(warning, systemImage: "speaker.slash")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .help(warning)
                }
                if let warning = recorder.micWarning, isLive {
                    Label(warning, systemImage: "mic.slash")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .help(warning)
                }
                Spacer()
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(CoastalTheme.surface.opacity(0.45))
    }

    // MARK: - Tabs

    @ViewBuilder
    private func content(_ meeting: Meeting) -> some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(DetailTab.allCases, id: \.self) { t in
                    Label(t.rawValue, systemImage: t.icon).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            switch tab {
            case .notes:
                NotesEditor(meetingID: meetingID)
            case .transcript:
                TranscriptView(meetingID: meetingID)
            case .enhanced:
                EnhancedNotesView(meetingID: meetingID, enhancing: enhancing, onEnhance: { enhance() })
            case .ask:
                AskView(meetingID: meetingID)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func toolbarContent(_ meeting: Meeting) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if isLive {
                Button {
                    Task { await recorder.stop() }
                } label: {
                    Label("Parar", systemImage: "stop.circle.fill")
                        .foregroundStyle(.red)
                }
                .help("Parar gravação (⌘.)")
            } else {
                Button {
                    Task { await recorder.start(meetingID: meetingID) }
                } label: {
                    Label("Gravar", systemImage: "record.circle")
                }
                .help("Gravar nesta reunião")
                .disabled(recorder.isRecording)
            }

            Button {
                enhance()
            } label: {
                if enhancing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Aprimorar", systemImage: "sparkles")
                }
            }
            .help("Combinar suas anotações com a transcrição em uma nota completa")
            .disabled(enhancing || isLive || (!meeting.hasTranscript && meeting.notesMD.isEmpty))

            Menu {
                Button("Copiar prompt para Hermes (SESI)") {
                    copyHermesPrompt(meeting)
                }
                .disabled(!meeting.hasTranscript && meeting.notesMD.isEmpty)

                Divider()

                Button("Copiar anotação aprimorada") { copy(meeting.enhancedMD ?? "") }
                    .disabled(meeting.enhancedMD == nil)
                Button("Copiar transcrição") { copy(MeetingStore.transcriptMarkdown(meeting)) }
                    .disabled(!meeting.hasTranscript)
                Button("Copiar anotações") { copy(meeting.notesMD) }
                    .disabled(meeting.notesMD.isEmpty)
                Divider()
                Button("Mostrar arquivos no Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.folder(for: meeting)])
                }
                Divider()
                Button("Transcrever novamente a partir do áudio") {
                    recorder.retranscribe(meetingID: meetingID)
                }
                .disabled(isLive)
            } label: {
                Label("Mais", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: - Actions

    private func enhance() {
        guard let meeting, !enhancing else { return }
        enhancing = true
        Task {
            defer { enhancing = false }
            do {
                let md = try await Enhancer(settings: settings).enhance(meeting: meeting)
                store.setEnhanced(meetingID, markdown: md)
                tab = .enhanced
            } catch {
                enhanceError = error.localizedDescription
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyHermesPrompt(_ meeting: Meeting) {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "pt_BR")
        dateFormatter.dateFormat = "dd/MM/yyyy HH:mm"
        let dataFormatada = dateFormatter.string(from: meeting.createdAt)

        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let prefixoArquivo = dateFormatter.string(from: meeting.createdAt)

        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dataISO = dateFormatter.string(from: meeting.createdAt)

        let duracao = formatClock(meeting.durationSeconds)
        let transcricao = MeetingStore.transcriptMarkdown(meeting)
        let rascunho = meeting.notesMD.isEmpty ? "Nenhum rascunho manual registrado." : meeting.notesMD

        let prompt = """
Por favor, processe esta reunião gravada no Muesli e crie a Ata Executiva padronizada no meu cofre do Obsidian (SESI).

### Arquivo Alvo:
- **Caminho:** `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Cofre pessoal/10-SESI/Reunioes/\(prefixoArquivo) - \(meeting.title).md`

### Metadados da Reunião:
- **Título:** \(meeting.title)
- **Data:** \(dataFormatada)
- **Duração:** \(duracao)

### Anotações de Rascunho:
\(rascunho)

### Transcrição Completa:
\(transcricao)

---
### Diretrizes de Estruturação (Template Padrão SESI):
1. **Frontmatter YAML:**
```yaml
---
tipo: reuniao
data: \(dataISO)
duracao: "\(duracao)"
participantes:
  - "Natan Mendes"
tags: [reuniao/executiva]
---
```
2. **Cabeçalho Executivo:**
- `# 📋 Ata Executiva de Reunião: \(meeting.title)`
- `- **Data:** \(dataFormatada)`
- `- **Duração:** \(duracao)`
- `- **Participantes:** Natan Mendes`
3. **## 📌 Deliberações e Discussão Técnica:**
- Tópicos numerados (`### 1. [Tópico]`) contendo `- **Contexto Técnico:**` e `- **Status/Decisão:**`.
4. **## 🎯 Plano de Ação:**
- Tabela Markdown com colunas: `| Ação | Responsável | Prazo / Momento |`.
"""

        copy(prompt)
    }
}
