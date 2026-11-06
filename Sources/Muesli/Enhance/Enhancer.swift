import Foundation

enum EnhanceError: LocalizedError {
    case noAPIKey
    case http(Int, String)
    case badResponse
    case nothingToEnhance

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No Anthropic API key set. Add one in Settings → AI, or switch to Ollama."
        case .http(let code, let message):
            return "AI request failed (HTTP \(code)): \(message)"
        case .badResponse:
            return "The AI returned an unexpected response."
        case .nothingToEnhance:
            return "Nothing to enhance yet — record a meeting or type some notes first."
        }
    }
}

/// Turns rough notes + transcript into polished notes, and answers questions
/// about a meeting. Two backends: the Anthropic Messages API and Ollama.
struct Enhancer {
    let settings: AppSettings

    static let baseSystemPrompt = """
    Você é o Muesli, um editor especializado em anotações de reuniões. Transforme as anotações fragmentadas do \
    usuário e a transcrição bruta em uma nota de reunião clara e bem estruturada, sempre em português do Brasil.

    Regras:
    - As anotações rápidas indicam o que o usuário considera importante. Preserve estrutura, ênfase e intenção; \
    expanda abreviações em ideias completas.
    - Use a transcrição para corrigir nomes, números e fatos, preencher lacunas e incluir decisões, \
    compromissos, itens de ação e questões em aberto relevantes.
    - Na transcrição, "Eu" é a pessoa que toma notas; "Outros" são os demais participantes.
    - A transcrição é gerada automaticamente e pode conter erros. Prefira interpretações coerentes com o contexto. \
    Se a gravação duplicar uma frase entre canais, atribua-a de modo sensato.
    - Nunca invente fatos ausentes nas anotações e na transcrição. Marque pontos realmente incertos como "(não ficou claro)".
    - Escreva em linguagem direta, sem jargão corporativo.
    - Retorne apenas Markdown limpo, sem preâmbulo ou bloco de código. Comece com "# Título" específico e concreto \
    (de 3 a 8 palavras). Não use o rótulo "TL;DR"; use sempre "## Resumo".
    """

    // MARK: - Public API

    func enhance(meeting: Meeting) async throws -> String {
        let transcriptMD = MeetingStore.transcriptMarkdown(meeting)
        guard meeting.hasTranscript || !meeting.notesMD.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EnhanceError.nothingToEnhance
        }
        let template = NoteTemplate.byID(meeting.templateID)
        let system = Enhancer.baseSystemPrompt + "\n\n" + template.instructions

        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .short

        var user = """
        Reunião: \(meeting.title)
        Data: \(df.string(from: meeting.createdAt))
        Duração: \(formatClock(meeting.durationSeconds))
        Modelo: \(template.name)

        ## Minhas anotações rápidas
        \(meeting.notesMD.isEmpty ? "(nenhuma — construa a nota apenas a partir da transcrição)" : meeting.notesMD)

        ## Transcrição
        """
        user += "\n" + clamp(transcriptMD.isEmpty ? "(sem transcrição — organize apenas as anotações rápidas)" : transcriptMD)
        user += "\n\nEscreva agora a nota de reunião aprimorada."

        return try await complete(system: system, messages: [["role": "user", "content": user]], maxTokens: 8192)
    }

    func ask(meeting: Meeting, history: [ChatMessage], question: String) async throws -> String {
        let transcriptMD = MeetingStore.transcriptMarkdown(meeting)
        let system = """
        Você é o Muesli e responde a perguntas sobre uma reunião específica. Baseie cada resposta exclusivamente \
        no registro abaixo. Se ele não trouxer a resposta, diga isso claramente. Quando útil, cite momentos como \
        [mm:ss]. "Eu" é o usuário; "Outros" são os demais participantes. Seja conciso e responda em português do Brasil.

        ## Anotações rápidas do usuário
        \(meeting.notesMD.isEmpty ? "(nenhuma)" : meeting.notesMD)

        ## Transcrição
        \(clamp(transcriptMD.isEmpty ? "(nenhuma)" : transcriptMD, limit: 120_000))
        """
        var messages: [[String: String]] = []
        for m in history.suffix(12) {
            messages.append(["role": m.role, "content": m.text])
        }
        messages.append(["role": "user", "content": question])
        return try await complete(system: system, messages: messages, maxTokens: 2048)
    }

    /// Tiny connectivity check used by Settings and the CLI.
    func ping() async throws -> String {
        try await complete(system: "Responda exatamente: OK", messages: [["role": "user", "content": "ping"]], maxTokens: 16)
    }

    // MARK: - Backends

    private func complete(system: String, messages: [[String: String]], maxTokens: Int) async throws -> String {
        switch settings.provider {
        case .anthropic:
            return try await completeAnthropic(system: system, messages: messages, maxTokens: maxTokens)
        case .ollama:
            return try await completeOllama(system: system, messages: messages)
        case .openai:
            return try await completeOpenAI(system: system, messages: messages, maxTokens: maxTokens)
        }
    }

    private func completeAnthropic(system: String, messages: [[String: String]], maxTokens: Int) async throws -> String {
        let key = settings.anthropicKey
        guard !key.isEmpty else { throw EnhanceError.noAPIKey }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": settings.anthropicModel,
            "max_tokens": maxTokens,
            "temperature": 0.3,
            "system": system,
            "messages": messages,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = Self.errorMessage(from: data)
            throw EnhanceError.http(status, message)
        }

        struct AnthropicResponse: Decodable {
            struct Content: Decodable {
                let type: String
                let text: String?
            }
            let content: [Content]
        }
        guard let decoded = try? JSONDecoder().decode(AnthropicResponse.self, from: data),
              let text = decoded.content.first(where: { $0.type == "text" })?.text else {
            throw EnhanceError.badResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func completeOpenAI(system: String, messages: [[String: String]], maxTokens: Int) async throws -> String {
        let base = settings.openAIBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: base + "/chat/completions") else { throw EnhanceError.badResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let key = settings.openAIKey
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }

        var allMessages: [[String: String]] = [["role": "system", "content": system]]
        allMessages.append(contentsOf: messages)
        let body: [String: Any] = [
            "model": settings.openAIModel,
            "messages": allMessages,
            "max_tokens": maxTokens,
            "temperature": 0.3,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw EnhanceError.http(status, Self.errorMessage(from: data))
        }
        struct OpenAIResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        guard let decoded = try? JSONDecoder().decode(OpenAIResponse.self, from: data),
              let text = decoded.choices.first?.message.content,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EnhanceError.badResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func completeOllama(system: String, messages: [[String: String]]) async throws -> String {
        let base = settings.ollamaBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: base + "/api/chat") else { throw EnhanceError.badResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        var allMessages: [[String: String]] = [["role": "system", "content": system]]
        allMessages.append(contentsOf: messages)
        let body: [String: Any] = [
            "model": settings.ollamaModel,
            "messages": allMessages,
            "stream": false,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw EnhanceError.http(status, Self.errorMessage(from: data))
        }
        struct OllamaResponse: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        guard let decoded = try? JSONDecoder().decode(OllamaResponse.self, from: data) else {
            throw EnhanceError.badResponse
        }
        return decoded.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func errorMessage(from data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let err = obj["error"] as? [String: Any], let msg = err["message"] as? String { return msg }
            if let msg = obj["error"] as? String { return msg }
        }
        return String(data: data.prefix(300), encoding: .utf8) ?? "unknown error"
    }

    /// Ollama models have small context windows; Claude does not, but cap anyway.
    private func clamp(_ text: String, limit: Int? = nil) -> String {
        let cap = limit ?? (settings.provider == .ollama ? 24_000 : 350_000)
        guard text.count > cap else { return text }
        let tail = String(text.suffix(cap))
        return "(transcrição truncada — exibindo a parte mais recente)\n…\n" + tail
    }
}
