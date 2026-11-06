import Foundation
import SwiftUI

/// Owns every meeting on disk. Layout:
///
///     ~/Library/Application Support/Muesli/
///       models/                    whisper ggml models
///       meetings/<folder>/
///         meeting.json             source of truth
///         notes.md                 mirror of your rough notes
///         transcript.md            mirror of the transcript
///         enhanced.md              mirror of the AI-enhanced notes
///         mic.wav / system.wav     full-session audio (16 kHz mono)
///
/// The .md/.wav mirrors exist so your data is useful without Muesli.
@MainActor
final class MeetingStore: ObservableObject {
    @Published private(set) var meetings: [Meeting] = []

    let baseDir: URL
    let meetingsDir: URL

    init(baseDir: URL? = nil) {
        let root = baseDir ?? MeetingStore.defaultBaseDir()
        self.baseDir = root
        let configuredMeetingsDir = root.appendingPathComponent("meetings", isDirectory: true)
        // FileManager can enumerate an iCloud directory but returns no children
        // when it is addressed through a local symlink. Resolve it once so both
        // launch-time loading and all later writes target the real directory.
        self.meetingsDir = configuredMeetingsDir.resolvingSymlinksInPath()
        try? FileManager.default.createDirectory(at: meetingsDir, withIntermediateDirectories: true)
        load()
        seedWelcomeIfFirstRun()
    }

    nonisolated static func defaultBaseDir() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Muesli", isDirectory: true)
    }

    func meeting(_ id: UUID?) -> Meeting? {
        guard let id else { return nil }
        return meetings.first { $0.id == id }
    }

    func folder(for meeting: Meeting) -> URL {
        meetingsDir.appendingPathComponent(meeting.folderName, isDirectory: true)
    }

    // MARK: - Loading

    /// Re-read meetings from disk. The storage directory may be an iCloud-backed
    /// symlink, so reload whenever the app becomes active as well as on launch.
    func reload() {
        load()
    }

    private func load() {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(
            at: meetingsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        var loaded: [Meeting] = []
        for folder in folders {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let json = folder.appendingPathComponent("meeting.json")
            guard let data = try? Data(contentsOf: json) else { continue }
            do {
                var m = try JSONDecoder.muesli.decode(Meeting.self, from: data)
                // The on-disk directory, rather than JSON, is authoritative. It
                // lets imported/iCloud-synced meetings keep working after moves.
                m.folderName = folder.lastPathComponent
                loaded.append(m)
            } catch {
                NSLog("Muesli: could not decode meeting.json in %@: %@", folder.lastPathComponent, String(describing: error))
            }
        }
        meetings = loaded.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Mutations

    @discardableResult
    func createMeeting(title: String? = nil, templateID: String = "auto") -> Meeting {
        let id = UUID()
        let now = Date()
        let meeting = Meeting(
            id: id,
            title: title ?? Meeting.defaultTitle(for: now),
            createdAt: now,
            templateID: templateID,
            folderName: Meeting.makeFolderName(for: now, id: id)
        )
        meetings.insert(meeting, at: 0)
        persist(meeting)
        return meeting
    }

    func update(_ meeting: Meeting) {
        guard let idx = meetings.firstIndex(where: { $0.id == meeting.id }) else { return }
        meetings[idx] = meeting
        persist(meeting)
    }

    func updateNotes(_ id: UUID, notes: String) {
        guard var m = meeting(id) else { return }
        m.notesMD = notes
        update(m)
    }

    func updateTitle(_ id: UUID, title: String) {
        guard var m = meeting(id), !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        m.title = title
        update(m)
    }

    func updateTemplate(_ id: UUID, templateID: String) {
        guard var m = meeting(id) else { return }
        m.templateID = templateID
        update(m)
    }

    func setEnhanced(_ id: UUID, markdown: String) {
        guard var m = meeting(id) else { return }
        m.enhancedMD = markdown
        // Lift a "# Title" first line into the meeting title if the user never renamed it.
        if m.isDefaultTitle,
           let first = markdown.split(separator: "\n").first,
           first.hasPrefix("# ") {
            let lifted = first.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if !lifted.isEmpty { m.title = lifted }
        }
        update(m)
    }

    func setDuration(_ id: UUID, seconds: Double) {
        guard var m = meeting(id) else { return }
        m.durationSeconds = seconds
        update(m)
    }

    func appendSegments(_ id: UUID, segments: [TranscriptSegment]) {
        guard var m = meeting(id), !segments.isEmpty else { return }
        m.transcript.append(contentsOf: segments)
        m.transcript.sort { $0.start < $1.start }
        update(m)
    }

    func clearTranscript(_ id: UUID) {
        guard var m = meeting(id) else { return }
        m.transcript = []
        update(m)
    }

    func appendChat(_ id: UUID, message: ChatMessage) {
        guard var m = meeting(id) else { return }
        m.chat.append(message)
        update(m)
    }

    func delete(_ meeting: Meeting) {
        meetings.removeAll { $0.id == meeting.id }
        let folder = folder(for: meeting)
        try? FileManager.default.trashItem(at: folder, resultingItemURL: nil)
    }

    // MARK: - Persistence

    private func persist(_ meeting: Meeting) {
        let folder = folder(for: meeting)
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder.muesli.encode(meeting) {
            try? data.write(to: folder.appendingPathComponent("meeting.json"), options: .atomic)
        }
        // Plain-file mirrors.
        try? meeting.notesMD.write(to: folder.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        if let enhanced = meeting.enhancedMD {
            try? enhanced.write(to: folder.appendingPathComponent("enhanced.md"), atomically: true, encoding: .utf8)
        }
        if meeting.hasTranscript {
            let md = MeetingStore.transcriptMarkdown(meeting)
            try? md.write(to: folder.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
        }
    }

    nonisolated static func transcriptMarkdown(_ meeting: Meeting) -> String {
        var out = "# Transcript — \(meeting.title)\n\n"
        for group in meeting.transcript.coalesced() {
            out += "**[\(formatClock(group.start))] \(group.speaker.label):** \(group.text)\n\n"
        }
        return out
    }

    // MARK: - Welcome meeting

    private func seedWelcomeIfFirstRun() {
        let flag = baseDir.appendingPathComponent(".welcomed")
        guard !FileManager.default.fileExists(atPath: flag.path), meetings.isEmpty else { return }
        var m = createMeeting(title: "Boas-vindas ao Muesli 🥣")
        m.notesMD = WelcomeContent.notes
        m.transcript = WelcomeContent.transcript
        m.enhancedMD = WelcomeContent.enhanced
        m.durationSeconds = 94
        update(m)
        try? Data().write(to: flag)
    }
}

enum WelcomeContent {
    static let notes = """
    - Muesli = anotador de reuniões de código aberto
    - escreva anotações rápidas durante a chamada; fragmentos servem
    - o Whisper roda localmente → a transcrição permanece neste Mac
    - selecione ✨ Aprimorar depois → Claude, 9router ou Ollama combinam anotações e transcrição
    """

    static let transcript: [TranscriptSegment] = [
        .init(speaker: .them, start: 2, end: 8, text: "A ideia central é simples: você faz anotações rápidas enquanto conversa e o aplicativo registra quem disse cada coisa."),
        .init(speaker: .me, start: 9, end: 14, text: "Certo — meu microfone é identificado como Eu, e as outras pessoas chegam pelo áudio do sistema como Outros."),
        .init(speaker: .them, start: 15, end: 24, text: "A transcrição usa o whisper.cpp no seu computador; nada sai do Mac a menos que você peça o aprimoramento."),
        .init(speaker: .me, start: 25, end: 33, text: "Quando a chamada acaba, seleciono Aprimorar, e meus fragmentos viram uma nota completa com base na transcrição."),
        .init(speaker: .them, start: 34, end: 41, text: "Exatamente. Itens de ação, decisões e questões em aberto são extraídos automaticamente. Suas anotações definem a ênfase."),
    ]

    static let enhanced = """
    # Boas-vindas ao Muesli

    ## Resumo
    O Muesli é um anotador de reuniões de código aberto e local. Ele captura seu microfone e o áudio do sistema do Mac sem adicionar um bot à chamada, transcreve tudo localmente com o Whisper e transforma suas anotações rápidas em uma nota organizada com IA.

    ## Como uma reunião funciona
    - Selecione **Iniciar reunião** antes ou durante uma chamada — funciona com Zoom, Meet, Teams ou qualquer aplicativo que produza áudio.
    - Escreva fragmentos em **Anotações** enquanto conversa. Não é necessário escrever de forma elaborada.
    - Acompanhe a aba **Transcrição**: *Eu* representa seu microfone e *Outros* representa o áudio da chamada.

    ## Depois da chamada
    - Selecione **✨ Aprimorar** para reescrever suas anotações usando a transcrição como fonte.
    - Use **Perguntar** para consultar a reunião, por exemplo: "o que decidimos sobre preços?".

    ## Itens de ação
    - [ ] Abra **Ajustes → Transcrição** e confirme que o modelo Whisper foi baixado
    - [ ] Configure uma chave da API Anthropic, 9router ou Ollama em **Ajustes → IA**
    - [ ] Conceda as permissões de microfone e gravação de tela quando solicitado

    ## Questões em aberto
    - Qual será sua primeira reunião gravada?
    """
}

extension JSONEncoder {
    static var muesli: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

extension JSONDecoder {
    static var muesli: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
