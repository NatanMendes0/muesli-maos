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
                .font(.system(size: 14, weight: .regular))
                .lineSpacing(4)
                .foregroundStyle(CoastalTheme.text)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

            if draft.isEmpty {
                Text("Faça suas anotações rápidas aqui durante a reunião. Tópicos, palavras-chave, decisões...\nO Muesli expande tudo com a transcrição ao finalizar ou ao clicar em Aprimorar.")
                    .foregroundStyle(CoastalTheme.faintText)
                    .font(.system(size: 14))
                    .padding(.horizontal, 25)
                    .padding(.vertical, 24)
                    .allowsHitTesting(false)
            }
        }
        .background(CoastalTheme.surface)
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
                try? await Task.sleep(nanoseconds: 600_000_000)
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
