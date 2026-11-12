import Foundation

/// Who said a given transcript segment.
/// "me" comes from the microphone stream, "them" from system audio (everyone else on the call).
enum Speaker: String, Codable {
    case me
    case them

    var label: String {
        switch self {
        case .me: return "Eu"
        case .them: return "Outros"
        }
    }
}

struct TranscriptSegment: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var speaker: Speaker
    /// Seconds from the start of the meeting.
    var start: Double
    var end: Double
    var text: String
}

struct ChatMessage: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var role: String // "user" | "assistant"
    var text: String
    var date: Date = Date()
}

struct Meeting: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var createdAt: Date = Date()
    var durationSeconds: Double = 0
    var templateID: String = "auto"
    var notesMD: String = ""
    var enhancedMD: String?
    var transcript: [TranscriptSegment] = []
    var chat: [ChatMessage] = []
    /// Folder name inside the meetings directory. Stable for the meeting's lifetime.
    var folderName: String
    var isManualTitle: Bool = false

    init(id: UUID = UUID(), title: String, createdAt: Date = Date(),
         durationSeconds: Double = 0, templateID: String = "auto",
         notesMD: String = "", enhancedMD: String? = nil,
         transcript: [TranscriptSegment] = [], chat: [ChatMessage] = [],
         folderName: String, isManualTitle: Bool = false) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.templateID = templateID
        self.notesMD = notesMD
        self.enhancedMD = enhancedMD
        self.transcript = transcript
        self.chat = chat
        self.folderName = folderName
        self.isManualTitle = isManualTitle
    }

    enum CodingKeys: String, CodingKey {
        case id, title, createdAt, durationSeconds, templateID, notesMD, enhancedMD, transcript, chat, folderName, isManualTitle
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0
        templateID = try c.decodeIfPresent(String.self, forKey: .templateID) ?? "auto"
        notesMD = try c.decodeIfPresent(String.self, forKey: .notesMD) ?? ""
        enhancedMD = try c.decodeIfPresent(String.self, forKey: .enhancedMD)
        transcript = try c.decodeIfPresent([TranscriptSegment].self, forKey: .transcript) ?? []
        chat = try c.decodeIfPresent([ChatMessage].self, forKey: .chat) ?? []
        folderName = try c.decode(String.self, forKey: .folderName)
        isManualTitle = try c.decodeIfPresent(Bool.self, forKey: .isManualTitle) ?? false
    }

    var hasTranscript: Bool { !transcript.isEmpty }

    var isDefaultTitle: Bool {
        title.hasPrefix("Reunião · ") || title.hasPrefix("Meeting · ") || title == "Nova reunião"
    }

    static func defaultTitle(for date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = "HH:mm"
        return "Reunião · \(f.string(from: date))"
    }

    static func makeFolderName(for date: Date = Date(), id: UUID) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return "\(f.string(from: date))-\(id.uuidString.prefix(8))"
    }
}

extension Array where Element == TranscriptSegment {
    /// Groups consecutive segments by the same speaker into readable paragraphs.
    func coalesced(maxGap: Double = 6, maxSpan: Double = 45) -> [(id: UUID, speaker: Speaker, start: Double, text: String)] {
        var groups: [(id: UUID, speaker: Speaker, start: Double, end: Double, text: String)] = []
        for seg in self.sorted(by: { $0.start < $1.start }) {
            let t = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            if var last = groups.last,
               last.speaker == seg.speaker,
               seg.start - last.end <= maxGap,
               seg.end - last.start <= maxSpan {
                last.text += " " + t
                last.end = Swift.max(last.end, seg.end)
                groups[groups.count - 1] = last
            } else {
                groups.append((seg.id, seg.speaker, seg.start, seg.end, t))
            }
        }
        return groups.map { ($0.id, $0.speaker, $0.start, $0.text) }
    }
}

func formatClock(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    if s >= 3600 {
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
    return String(format: "%d:%02d", s / 60, s % 60)
}
