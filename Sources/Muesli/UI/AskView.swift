import SwiftUI

/// Bottom chat dock for asking questions about a meeting, matching Muesli Windows.
struct AskDockView: View {
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var settings: AppSettings
    let meetingID: UUID
    @Binding var expanded: Bool

    @State private var question = ""
    @State private var thinking = false
    @State private var errorText: String?
    @FocusState private var fieldFocused: Bool

    private var meeting: Meeting? { store.meeting(meetingID) }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar with quick prompts
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.up")
                            .font(.system(size: 10.5, weight: .bold))
                        Text("Perguntar à IA")
                            .font(.system(size: 12, weight: .semibold))
                        if let count = meeting?.chat.count, count > 0 {
                            Text("(\(count))")
                                .font(.system(size: 11))
                                .foregroundStyle(CoastalTheme.secondaryText)
                        }
                    }
                    .foregroundStyle(CoastalTheme.text)
                }
                .buttonStyle(.plain)

                Spacer()

                if settings.hasAIConfigured {
                    QuickPromptChip(title: "Plano de ação") {
                        send(custom: "Liste todos os itens de ação, responsáveis e prazos combinados nesta reunião.")
                    }
                    QuickPromptChip(title: "Email de follow-up") {
                        send(custom: "Escreva um e-mail curto de follow-up resumindo os principais pontos e próximos passos.")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(CoastalTheme.surfaceSoft)

            if expanded {
                if let chat = meeting?.chat, !chat.isEmpty || thinking || errorText != nil {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(chat) { message in
                                    DockBubble(message: message).id(message.id)
                                }
                                if thinking {
                                    HStack(spacing: 6) {
                                        ProgressView().controlSize(.mini)
                                        Text("Analisando reunião…")
                                            .font(.caption)
                                            .foregroundStyle(CoastalTheme.secondaryText)
                                    }
                                    .id("thinking")
                                }
                                if let errorText {
                                    Label(errorText, systemImage: "exclamationmark.triangle")
                                        .font(.caption)
                                        .foregroundStyle(CoastalTheme.danger)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .frame(maxHeight: 165)
                        .background(CoastalTheme.surface)
                        .onChange(of: chat.count) { _, _ in
                            if let last = chat.last?.id {
                                withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField(
                        settings.hasAIConfigured
                            ? "Pergunte qualquer coisa sobre esta reunião…"
                            : "Configure uma chave de IA em Configurações para perguntar…",
                        text: $question
                    )
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(CoastalTheme.text)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(CoastalTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(CoastalTheme.separator, lineWidth: 1))
                    .focused($fieldFocused)
                    .onSubmit { send(custom: nil) }
                    .disabled(!settings.hasAIConfigured || thinking)

                    Button { send(custom: nil) } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(question.isEmpty ? CoastalTheme.faintText : CoastalTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(question.isEmpty || thinking || !settings.hasAIConfigured)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(CoastalTheme.surfaceSoft)
            }
        }
    }

    private func send(custom: String?) {
        let q = (custom ?? question).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !thinking, let meeting else { return }
        if custom == nil { question = "" }
        expanded = true
        errorText = nil
        store.appendChat(meetingID, message: ChatMessage(role: "user", text: q))
        thinking = true
        Task {
            defer { thinking = false }
            do {
                let history = store.meeting(meetingID)?.chat.dropLast().map { $0 } ?? []
                let answer = try await Enhancer(settings: settings).ask(
                    meeting: meeting,
                    history: Array(history),
                    question: q
                )
                store.appendChat(meetingID, message: ChatMessage(role: "assistant", text: answer))
            } catch {
                errorText = error.localizedDescription
            }
            fieldFocused = true
        }
    }
}

private struct QuickPromptChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(CoastalTheme.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(CoastalTheme.surface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(CoastalTheme.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct DockBubble: View {
    let message: ChatMessage

    var body: some View {
        if message.role == "user" {
            HStack {
                Spacer(minLength: 60)
                Text(message.text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(CoastalTheme.text)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(CoastalTheme.accentSoft, in: RoundedRectangle(cornerRadius: 10))
                    .textSelection(.enabled)
            }
        } else {
            MarkdownView(markdown: message.text)
                .font(.system(size: 13))
                .padding(.trailing, 30)
        }
    }
}
