import Foundation

enum EnhanceError: LocalizedError {
    case notConfigured
    case emptyResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Nenhum provedor de IA configurado. Adicione uma chave (Groq, Gemini, OpenAI, Claude) ou selecione o Ollama em Configurações → Modelos de IA."
        case .emptyResponse:
            return "O modelo retornou uma resposta vazia."
        case .httpError(let code, let body):
            return "Erro da IA (HTTP \(code)): \(body)"
        }
    }
}

/// Calls Groq, Google Gemini, OpenAI (or compatible), Anthropic Claude, or local Ollama.
/// Supports multi-key rotation via KeyRotator, <think> stripping, AI title generation,
/// Copilot SESI prompt export, and Obsidian Markdown export.
@MainActor
final class Enhancer {
    private let provider: AIProvider
    private let groqKeys: [String]
    private let groqModel: String
    private let geminiKeys: [String]
    private let geminiModel: String
    private let openAIKeys: [String]
    private let openAIModel: String
    private let openAIBaseURL: String
    private let anthropicKeys: [String]
    private let anthropicModel: String
    private let ollamaURL: String
    private let ollamaModel: String
    private let hasAnyAI: Bool

    init(settings: AppSettings) {
        self.provider = settings.aiProvider
        self.groqKeys = KeychainHelper.cleanKeys(settings.groqKeys)
        self.groqModel = settings.groqModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "qwen/qwen3.8-27b"
            : settings.groqModel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.geminiKeys = KeychainHelper.cleanKeys(settings.geminiKeys)
        self.geminiModel = settings.geminiModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "gemini-2.5-flash"
            : settings.geminiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.openAIKeys = KeychainHelper.cleanKeys(settings.openAIKeys)
        self.openAIModel = settings.openAIModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "gpt-4o-mini"
            : settings.openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = settings.openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.openAIBaseURL = base.isEmpty ? "https://api.openai.com/v1" : base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.anthropicKeys = KeychainHelper.cleanKeys(settings.anthropicKeys)
        self.anthropicModel = settings.anthropicModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "claude-haiku-4-5-20251001"
            : settings.anthropicModel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.ollamaURL = settings.ollamaBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "http://localhost:11434"
            : settings.ollamaBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.ollamaModel = settings.ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.hasAnyAI = settings.hasAIConfigured
    }

    // MARK: - Public

    func enhance(meeting: Meeting) async throws -> String {
        guard hasAnyAI else { throw EnhanceError.notConfigured }
        let template = MeetingTemplate.find(meeting.templateID)
        let notes = meeting.notesMD.trimmingCharacters(in: .whitespacesAndNewlines)
        let transcript = Self.formatTranscript(meeting.transcript, charBudget: charBudgetForCurrentConfig())

        if notes.isEmpty && transcript.isEmpty {
            return "*Nada para aprimorar ainda: sem anotações nem transcrição.*"
        }

        let df = DateFormatter()
        df.locale = Locale(identifier: "pt_BR")
        df.dateStyle = .long
        df.timeStyle = .short

        let userPrompt = """
        Título da reunião: \(meeting.title)
        Data: \(df.string(from: meeting.createdAt))
        Duração: \(formatClock(meeting.durationSeconds))
        Modelo de ata: \(template.name)
        Seções obrigatórias a produzir (use exatamente estes títulos como H2 ##):
        \(template.promptBlock)

        Anotações rápidas do usuário durante a reunião:
        \(notes.isEmpty ? "(nenhuma anotação manual)" : notes)

        Transcrição completa (Eu = microfone do usuário, Outros = demais participantes):
        \(transcript.isEmpty ? "(nenhuma transcrição capturada)" : transcript)
        """

        let raw = try await complete(system: Self.enhanceSystemPrompt, user: userPrompt, maxTokens: 4096)
        return Self.stripThink(raw)
    }

    func ask(meeting: Meeting, history: [ChatMessage], question: String) async throws -> String {
        guard hasAnyAI else { throw EnhanceError.notConfigured }
        let transcript = Self.formatTranscript(meeting.transcript, charBudget: charBudgetForCurrentConfig())
        var context = "Reunião: \(meeting.title)\n"
        if !meeting.notesMD.isEmpty { context += "\nAnotações:\n\(meeting.notesMD)\n" }
        if let enhanced = meeting.enhancedMD, !enhanced.isEmpty {
            context += "\nAta aprimorada:\n\(enhanced)\n"
        }
        context += "\nTranscrição:\n\(transcript.isEmpty ? "(sem transcrição)" : transcript)"

        var messages: [(role: String, content: String)] = []
        messages.append(("user", "Contexto da reunião para referência:\n\n\(context)"))
        messages.append(("assistant", "Entendido. Pode perguntar sobre esta reunião."))
        for m in history.suffix(12) {
            messages.append((m.role == "assistant" ? "assistant" : "user", m.text))
        }
        messages.append(("user", question))

        let raw = try await completeChat(system: Self.askSystemPrompt, messages: messages, maxTokens: 2048)
        return Self.stripThink(raw)
    }

    func suggestTitle(meeting: Meeting, enhancedMD: String = "") async -> String {
        guard hasAnyAI else { return "" }
        let notes = meeting.notesMD.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = enhancedMD.trimmingCharacters(in: .whitespacesAndNewlines)
        let snippet = Self.formatTranscript(Array(meeting.transcript.prefix(25)), charBudget: 2500)
        if summary.isEmpty && notes.isEmpty && snippet.isEmpty { return "" }

        var parts: [String] = []
        if !summary.isEmpty {
            parts.append("Resumo aprimorado da reunião:\n" + String(summary.prefix(3500)))
        }
        if !notes.isEmpty {
            parts.append("Anotações do usuário:\n" + String(notes.prefix(1000)))
        }
        if !snippet.isEmpty && summary.count < 400 {
            parts.append("Trecho da transcrição:\n" + String(snippet.prefix(2000)))
        }

        guard let raw = try? await complete(system: Self.titleSystemPrompt, user: parts.joined(separator: "\n\n"), maxTokens: 80) else {
            return ""
        }
        return Self.cleanSuggestedTitle(raw)
    }

    func ping() async throws -> String {
        let reply = try await complete(
            system: "Responda em português com no máximo 5 palavras.",
            user: "Diga 'Conexão OK' para confirmar que a API está funcionando.",
            maxTokens: 40
        )
        return Self.stripThink(reply)
    }

    func testProvider(_ target: AIProvider) async throws -> String {
        let reply = try await dispatch(
            provider: target,
            system: "Responda exatamente: Conexão OK",
            messages: [("user", "ping")],
            maxTokens: 20
        )
        return Self.stripThink(reply)
    }

    // MARK: - Static Prompts & Formatters

    static let enhanceSystemPrompt = """
    Você é um especialista em atas e anotações executivas de reuniões.
    Você recebe as anotações rápidas do usuário mais a transcrição em tempo real da reunião.
    Produza anotações de reunião limpas, objetivas e estruturadas em Markdown, em português brasileiro.

    Regras:
    - As notas rápidas do usuário são âncoras essenciais: tudo o que foi anotado deve constar no documento, expandido com os detalhes da transcrição. Se algo anotado não tiver correspondência clara na transcrição, mantenha como foi escrito.
    - Extraia os tópicos mais importantes, o contexto técnico e as discussões relevantes.
    - Registre decisões e deliberações com clareza.
    - Ações e tarefas devem especificar responsáveis e prazos/momentos sempre que mencionados (use caixas de seleção `- [ ]` ou tabela Markdown `| Ação / Tarefa | Responsável | Prazo / Momento |`).
    - Nunca invente fatos, nomes, prazos ou números que não foram ditos na reunião.
    - Seja específico: cite nomes de pessoas, sistemas, ferramentas e prazos. Prefira tópicos (bullet points) objetivos em vez de longos blocos de texto.
    - Use exatamente os títulos de seção fornecidos como H2 (##) em Markdown. Omita uma seção apenas se realmente não houver nada referente a ela.
    - Não use travessões longos nem prefácios. Responda apenas com o Markdown gerado.
    """

    static let askSystemPrompt = """
    Você responde perguntas sobre uma reunião gravada com base apenas nas anotações e na transcrição fornecidas.
    Responda em português brasileiro, de forma direta, objetiva e concisa.
    Cite quem disse o quê (Eu vs. Outros) quando relevante. Se a informação não estiver na transcrição ou nas anotações, diga claramente que não foi mencionada.
    """

    static let titleSystemPrompt = """
    Você cria títulos curtos, claros e descritivos para reuniões em português brasileiro.
    Regras:
    - Responda APENAS com o título da reunião (entre 3 e 7 palavras).
    - Foque no tema, projeto, sistema ou decisão central discutida.
    - Nunca use aspas, ponto final, marcações Markdown (#, *), prefixos como 'Título:' nem explicações.
    """

    nonisolated static func cleanSuggestedTitle(_ raw: String) -> String {
        let stripped = stripThink(raw)
        var line = stripped.components(separatedBy: .newlines).first ?? ""
        let trimSet = CharacterSet(charactersIn: " \"'`*•.-:#\t")
        line = line.trimmingCharacters(in: trimSet)
        if let regex = try? NSRegularExpression(pattern: "^(?:t[ií]tulo\\s*:\\s*|#|\"|'|\\s)+", options: .caseInsensitive) {
            let range = NSRange(line.startIndex..., in: line)
            line = regex.stringByReplacingMatches(in: line, range: range, withTemplate: "")
        }
        line = line.trimmingCharacters(in: trimSet)
        if line.count > 90 {
            let prefix = String(line.prefix(87))
            if let lastSpace = prefix.lastIndex(of: " ") {
                line = String(prefix[..<lastSpace]) + "..."
            } else {
                line = prefix + "..."
            }
        }
        return line
    }

    nonisolated static func stripThink(_ text: String) -> String {
        var out = text
        if let regex = try? NSRegularExpression(pattern: "<think>.*?</think>", options: [.dotMatchesLineSeparators]) {
            let range = NSRange(out.startIndex..., in: out)
            out = regex.stringByReplacingMatches(in: out, range: range, withTemplate: "")
        }
        if let idx = out.range(of: "<think>") {
            out = String(out[..<idx.lowerBound])
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func formatTranscript(_ segments: [TranscriptSegment], charBudget: Int) -> String {
        let coalesced = segments.coalesced()
        guard !coalesced.isEmpty else { return "" }
        let lines = coalesced.map { g in
            "[\(formatClock(g.start))] \(g.speaker.label): \(g.text)"
        }
        let full = lines.joined(separator: "\n")
        if full.count <= charBudget { return full }

        let headBudget = Int(Double(charBudget) * 0.25)
        let tailBudget = charBudget - headBudget - 60
        let head = String(full.prefix(headBudget))
        let tail = String(full.suffix(max(0, tailBudget)))
        return "\(head)\n\n[... trecho intermediário omitido para caber no contexto ...]\n\n\(tail)"
    }

    nonisolated static func buildCopilotPrompt(meeting: Meeting) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "pt_BR")
        dateFormatter.dateFormat = "dd/MM/yyyy HH:mm"
        let dateStr = dateFormatter.string(from: meeting.createdAt)

        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"
        let dateIso = isoFormatter.string(from: meeting.createdAt)

        let mins = Int(meeting.durationSeconds / 60)
        let duracaoStr = mins > 0 ? "\(mins) min" : "< 1 min"

        let coalesced = meeting.transcript.coalesced()
        let transcricao = coalesced.isEmpty
            ? "(Nenhuma transcrição capturada)"
            : coalesced.map { "[\(formatClock($0.start))] \($0.speaker.label): \($0.text)" }.joined(separator: "\n")

        let rascunho = meeting.notesMD.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Nenhum rascunho manual registrado."
            : meeting.notesMD.trimmingCharacters(in: .whitespacesAndNewlines)

        return """
        Por favor, processe esta reunião gravada e gere a Ata Executiva padronizada (padrão SESI) em formato Markdown pronto para uso no Obsidian/Notion.

        ### Metadados da Reunião:
        - **Título:** \(meeting.title)
        - **Data:** \(dateStr)
        - **Duração:** \(duracaoStr)

        ### Anotações Rápidas de Rascunho:
        \(rascunho)

        ### Transcrição Completa da Fala (Eu vs Outros):
        \(transcricao)

        ---
        ### Diretrizes de Estruturação Obrigatórias (Template SESI):
        1. **Frontmatter YAML (início do documento):**
        ```yaml
        ---
        tipo: reuniao
        data: \(dateIso)
        duracao: "\(duracaoStr)"
        participantes:
          - "Participante"
        tags: [reuniao/executiva]
        ---
        ```
        2. **Cabeçalho:**
        - `# 📋 Ata Executiva: \(meeting.title)`
        - `> 📅 **Data:** \(dateStr) · ⏱️ **Duração:** \(duracaoStr)`
        - `---`

        3. **## 📌 Resumo Executivo:**
        - Visão geral em 3 a 5 tópicos destacando o objetivo e as principais conclusões.

        4. **## 💡 Deliberações e Discussão Técnica:**
        - Tópicos numerados (`### 1. [Tema / Assunto]`) contendo:
          - `- **Contexto Técnico:**` O que foi discutido em detalhes.
          - `- **Status/Decisão:**` O que foi formalmente acordado ou definido.

        5. **## 🎯 Plano de Ação:**
        - Tabela Markdown estruturada exatamente com as colunas:
        `| Ação / Tarefa | Responsável | Prazo / Momento |`
        (Cada ação deve ter um responsável e prazo inferidos da conversa).
        """
    }

    nonisolated static func buildObsidianMarkdown(meeting: Meeting, includeTranscript: Bool) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "pt_BR")
        dateFormatter.dateFormat = "dd/MM/yyyy HH:mm"
        let dateStr = dateFormatter.string(from: meeting.createdAt)

        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"
        let dateIso = isoFormatter.string(from: meeting.createdAt)

        let mins = Int(meeting.durationSeconds / 60)
        let duracaoStr = mins > 0 ? "\(mins) min" : "< 1 min"

        var out: [String] = [
            "---",
            "tipo: reuniao",
            "data: \(dateIso)",
            "duracao: \"\(duracaoStr)\"",
            "tags: [reuniao]",
            "---",
            "",
            "# 📋 \(meeting.title)",
            "> 📅 **Data:** \(dateStr) · ⏱️ **Duração:** \(duracaoStr)",
            "---",
            "",
        ]
        if let enhanced = meeting.enhancedMD?.trimmingCharacters(in: .whitespacesAndNewlines), !enhanced.isEmpty {
            out += ["## 📌 Resumo & Pontos Chave", enhanced, ""]
        }
        let notes = meeting.notesMD.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            out += ["## ✍️ Anotações Rápidas", notes, ""]
        }
        if includeTranscript && !meeting.transcript.isEmpty {
            out.append("## 💬 Transcrição Completa")
            let lines = meeting.transcript.coalesced().map { "[\(formatClock($0.start))] **\($0.speaker.label):** \($0.text)" }
            out.append(lines.joined(separator: "\n"))
        }
        return out.joined(separator: "\n")
    }

    static func fetchOllamaModels(baseURL: String) async -> [String] {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmed)/api/tags") else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]]
        else { return [] }
        return models.compactMap { $0["name"] as? String }
    }

    // MARK: - Provider Routing & Multi-Key Rotation

    private func charBudgetForCurrentConfig() -> Int {
        let active: AIProvider
        if provider == .auto {
            if !groqKeys.isEmpty { active = .groq }
            else if !geminiKeys.isEmpty { active = .gemini }
            else if !anthropicKeys.isEmpty { active = .anthropic }
            else if !openAIKeys.isEmpty { active = .openai }
            else { active = .ollama }
        } else {
            active = provider
        }
        return active == .ollama ? 11_000 : 28_000
    }

    private func complete(system: String, user: String, maxTokens: Int) async throws -> String {
        try await completeChat(system: system, messages: [("user", user)], maxTokens: maxTokens)
    }

    private func completeChat(system: String, messages: [(role: String, content: String)], maxTokens: Int) async throws -> String {
        if provider != .auto {
            return try await dispatch(provider: provider, system: system, messages: messages, maxTokens: maxTokens)
        }

        var candidates: [AIProvider] = []
        if !groqKeys.isEmpty { candidates.append(.groq) }
        if !geminiKeys.isEmpty { candidates.append(.gemini) }
        if !anthropicKeys.isEmpty { candidates.append(.anthropic) }
        if !openAIKeys.isEmpty { candidates.append(.openai) }
        if !ollamaModel.isEmpty { candidates.append(.ollama) }

        guard !candidates.isEmpty else { throw EnhanceError.notConfigured }

        var lastError: Error = EnhanceError.notConfigured
        for p in candidates {
            do {
                return try await dispatch(provider: p, system: system, messages: messages, maxTokens: maxTokens)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func dispatch(provider: AIProvider, system: String, messages: [(role: String, content: String)], maxTokens: Int) async throws -> String {
        switch provider {
        case .groq:
            return try await callWithRotation(pool: "llm_groq", keys: groqKeys) { key in
                try await Self.callOpenAIStyle(
                    url: "https://api.groq.com/openai/v1/chat/completions",
                    key: key,
                    model: self.groqModel,
                    system: system,
                    messages: messages,
                    maxTokens: maxTokens
                )
            }
        case .gemini:
            return try await callWithRotation(pool: "llm_gemini", keys: geminiKeys) { key in
                try await Self.callGemini(
                    key: key,
                    model: self.geminiModel,
                    system: system,
                    messages: messages,
                    maxTokens: maxTokens
                )
            }
        case .openai:
            return try await callWithRotation(pool: "llm_openai", keys: openAIKeys) { key in
                let endpoint = self.openAIBaseURL.hasSuffix("/chat/completions")
                    ? self.openAIBaseURL
                    : "\(self.openAIBaseURL)/chat/completions"
                return try await Self.callOpenAIStyle(
                    url: endpoint,
                    key: key,
                    model: self.openAIModel,
                    system: system,
                    messages: messages,
                    maxTokens: maxTokens
                )
            }
        case .anthropic:
            return try await callWithRotation(pool: "llm_anthropic", keys: anthropicKeys) { key in
                try await Self.callAnthropic(
                    key: key,
                    model: self.anthropicModel,
                    system: system,
                    messages: messages,
                    maxTokens: maxTokens
                )
            }
        case .ollama:
            return try await Self.callOllama(
                baseURL: ollamaURL,
                model: ollamaModel,
                system: system,
                messages: messages
            )
        case .auto:
            throw EnhanceError.notConfigured
        }
    }

    private func callWithRotation(pool: String, keys: [String], block: (String) async throws -> String) async throws -> String {
        let ordered = KeyRotator.shared.orderedKeys(pool: pool, keys: keys)
        guard !ordered.isEmpty else { throw EnhanceError.notConfigured }

        var lastError: Error = EnhanceError.notConfigured
        for key in ordered {
            do {
                let res = try await block(key)
                KeyRotator.shared.markSuccess(pool: pool, key: key, allKeys: keys)
                return res
            } catch let err as EnhanceError {
                if case .httpError(let code, _) = err {
                    KeyRotator.shared.markFailure(pool: pool, key: key, statusCode: code)
                } else {
                    KeyRotator.shared.markFailure(pool: pool, key: key, statusCode: 0)
                }
                lastError = err
            } catch {
                KeyRotator.shared.markFailure(pool: pool, key: key, statusCode: 0)
                lastError = error
            }
        }
        throw lastError
    }

    // MARK: - HTTP Clients

    private static func errorMessage(from data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let err = obj["error"] as? [String: Any], let msg = err["message"] as? String { return msg }
            if let msg = obj["error"] as? String { return msg }
        }
        return String(data: data.prefix(300), encoding: .utf8) ?? "erro desconhecido"
    }

    private static func callOpenAIStyle(
        url urlString: String,
        key: String,
        model: String,
        system: String,
        messages: [(role: String, content: String)],
        maxTokens: Int
    ) async throws -> String {
        guard let url = URL(string: urlString) else { throw EnhanceError.httpError(0, "URL inválida: \(urlString)") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var apiMessages: [[String: String]] = [["role": "system", "content": system]]
        apiMessages += messages.map { ["role": $0.role, "content": $0.content] }

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.3,
            "max_tokens": maxTokens,
            "messages": apiMessages,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw EnhanceError.httpError(code, errorMessage(from: data))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let content = msg["content"] as? String
        else { throw EnhanceError.emptyResponse }
        let cleaned = stripThink(content)
        guard !cleaned.isEmpty else { throw EnhanceError.emptyResponse }
        return cleaned
    }

    private static func callGemini(
        key: String,
        model: String,
        system: String,
        messages: [(role: String, content: String)],
        maxTokens: Int
    ) async throws -> String {
        let cleanModel = model.hasPrefix("models/") ? String(model.dropFirst(7)) : model
        let encodedModel = cleanModel.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cleanModel
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent") else {
            throw EnhanceError.httpError(0, "Modelo Gemini inválido: \(model)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let contents: [[String: Any]] = messages.map { msg in
            [
                "role": msg.role == "assistant" ? "model" : "user",
                "parts": [["text": msg.content]],
            ]
        }

        let body: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": system]],
            ],
            "contents": contents,
            "generationConfig": [
                "temperature": 0.3,
                "maxOutputTokens": maxTokens,
            ],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw EnhanceError.httpError(code, errorMessage(from: data))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
        else { throw EnhanceError.emptyResponse }

        let text = parts.compactMap { $0["text"] as? String }.joined()
        let cleaned = stripThink(text)
        guard !cleaned.isEmpty else { throw EnhanceError.emptyResponse }
        return cleaned
    }

    private static func callAnthropic(
        key: String,
        model: String,
        system: String,
        messages: [(role: String, content: String)],
        maxTokens: Int
    ) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw EnhanceError.httpError(code, errorMessage(from: data))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]]
        else { throw EnhanceError.emptyResponse }
        let text = content.compactMap { $0["text"] as? String }.joined()
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw EnhanceError.emptyResponse }
        return cleaned
    }

    private static func callOllama(
        baseURL: String,
        model: String,
        system: String,
        messages: [(role: String, content: String)]
    ) async throws -> String {
        var chosenModel = model
        if chosenModel.isEmpty {
            let installed = await fetchOllamaModels(baseURL: baseURL)
            if let first = installed.first {
                chosenModel = first
            } else {
                throw EnhanceError.httpError(0, "Ollama não está rodando ou não possui modelos instalados.")
            }
        }
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw EnhanceError.httpError(0, "URL do Ollama inválida")
        }

        var apiMessages: [[String: String]] = [["role": "system", "content": system]]
        apiMessages += messages.map { ["role": $0.role, "content": $0.content] }

        func makeReq(includeThinkFlag: Bool) throws -> URLRequest {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = 300
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var body: [String: Any] = [
                "model": chosenModel,
                "messages": apiMessages,
                "stream": false,
                "options": ["temperature": 0.3, "num_ctx": 16384],
            ]
            if includeThinkFlag { body["think"] = false }
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            return req
        }

        var (data, resp) = try await URLSession.shared.data(for: try makeReq(includeThinkFlag: true))
        var code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 400 {
            (data, resp) = try await URLSession.shared.data(for: try makeReq(includeThinkFlag: false))
            code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        }
        guard (200..<300).contains(code) else {
            throw EnhanceError.httpError(code, errorMessage(from: data))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let text = message["content"] as? String
        else { throw EnhanceError.emptyResponse }

        let cleaned = stripThink(text)
        guard !cleaned.isEmpty else { throw EnhanceError.emptyResponse }
        return cleaned
    }
}
