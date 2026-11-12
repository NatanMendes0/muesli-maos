import SwiftUI

struct RecordBar: View {
    @EnvironmentObject private var recorder: RecordingController

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Circle()
                    .fill(CoastalTheme.danger)
                    .frame(width: 9, height: 9)
                Text("Gravando")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(CoastalTheme.danger)

                if case .recording(_, let started) = recorder.state {
                    TimelineView(.periodic(from: started, by: 1.0)) { context in
                        Text(formatClock(max(0, context.date.timeIntervalSince(started))))
                            .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(CoastalTheme.text)
                    }
                } else {
                    Text("0:00")
                        .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(CoastalTheme.text)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(CoastalTheme.dangerSoft, in: Capsule())

            LevelMeter(label: "Eu", level: recorder.micLevel)
            LevelMeter(label: "Outros", level: recorder.sysLevel)

            Spacer()

            if recorder.pendingChunks > 0 {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text("Transcrevendo (\(recorder.pendingChunks))")
                        .font(.caption)
                        .foregroundStyle(CoastalTheme.secondaryText)
                }
            }

            Button {
                Task { await recorder.stop() }
            } label: {
                Label("Parar", systemImage: "stop.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(CoastalTheme.danger, in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(".", modifiers: .command)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(CoastalTheme.surface)
    }
}

private struct LevelMeter: View {
    let label: String
    let level: Float

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CoastalTheme.secondaryText)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(CoastalTheme.separator)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(CoastalTheme.accent)
                        .frame(width: geo.size.width * CGFloat(min(1, max(0.03, level))))
                }
            }
            .frame(width: 56, height: 6)
        }
    }
}
