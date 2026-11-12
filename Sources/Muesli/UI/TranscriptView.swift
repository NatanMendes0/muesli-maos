import SwiftUI

struct TranscriptView: View {
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var recorder: RecordingController
    let meetingID: UUID

    private var meeting: Meeting? { store.meeting(meetingID) }

    var body: some View {
        let groups = meeting?.transcript.coalesced() ?? []

        if groups.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 28))
                    .foregroundStyle(CoastalTheme.faintText)
                Text(recorder.recordingMeetingID == meetingID
                     ? "Ouvindo… os blocos de transcrição aparecem a cada ~20s."
                     : "Nenhuma transcrição registrada ainda.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(CoastalTheme.secondaryText)
                    .multilineTextAlignment(.center)
                if recorder.recordingMeetingID != meetingID && hasAudioFiles {
                    Button("Transcrever áudio salvo") {
                        recorder.retranscribe(meetingID: meetingID)
                        recorder.showToast("Retranscrição local iniciada…")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CoastalTheme.btnInkFg)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(CoastalTheme.btnInkBg, in: RoundedRectangle(cornerRadius: 7))
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(groups, id: \.id) { g in
                            TranscriptRow(speaker: g.speaker, start: g.start, text: g.text)
                                .id(g.id)
                        }
                    }
                    .padding(14)
                }
                .onChange(of: groups.count) { _, _ in
                    if recorder.recordingMeetingID == meetingID, let last = groups.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }

    private var hasAudioFiles: Bool {
        guard let m = meeting else { return false }
        let dir = store.folder(for: m)
        let fm = FileManager.default
        return fm.fileExists(atPath: dir.appendingPathComponent("mic.wav").path)
            || fm.fileExists(atPath: dir.appendingPathComponent("system.wav").path)
    }
}

private struct TranscriptRow: View {
    let speaker: Speaker
    let start: Double
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(speaker.label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(speaker == .me ? CoastalTheme.accent : CoastalTheme.infoFg)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        speaker == .me ? CoastalTheme.accentSoft : CoastalTheme.infoBg,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                Text(formatClock(start))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(CoastalTheme.faintText)
            }
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(CoastalTheme.bodyText)
                .textSelection(.enabled)
        }
    }
}
