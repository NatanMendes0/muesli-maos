import SwiftUI

/// The rough-notes pad. Local draft state so typing stays smooth while the
/// transcript updates behind it; saves debounced.
struct NotesEditor: View {
    @EnvironmentObject private var store: MeetingStore
    let meetingID: UUID

    @State private var draft = ""
    @State private var loaded = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $draft)
                .font(.system(size: 14.5, weight: .regular, design: .rounded))
                .lineSpacing(4)
                .foregroundStyle(CoastalTheme.text)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 24)
                .padding(.vertical, 18)

            if draft.isEmpty {
                Text("Anote livremente durante a conversa — frases curtas servem.\nO Muesli combina suas anotações com a transcrição ao selecionar ✨ Aprimorar.")
                    .foregroundStyle(CoastalTheme.secondaryText.opacity(0.72))
                    .font(.system(size: 14.5, design: .rounded))
                    .padding(.horizontal, 29)
                    .padding(.vertical, 26)
                    .allowsHitTesting(false)
            }
        }
        .background(CoastalTheme.background)
        .onAppear {
            if !loaded {
                draft = store.meeting(meetingID)?.notesMD ?? ""
                loaded = true
            }
        }
        .onChange(of: draft) { _, newValue in
            guard loaded else { return }
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled else { return }
                store.updateNotes(meetingID, notes: newValue)
            }
        }
        .onDisappear {
            saveTask?.cancel()
            store.updateNotes(meetingID, notes: draft)
        }
    }
}
