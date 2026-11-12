import Foundation

enum CloudSTTError: LocalizedError {
    case noKeys(String)
    case httpError(String, Int, String)
    case invalidWAV

    var errorDescription: String? {
        switch self {
        case .noKeys(let provider):
            return "Nenhuma chave de API configurada para \(provider) em Configurações → Transcrição."
        case .httpError(let provider, let code, let detail):
            return "\(provider) (HTTP \(code)): \(detail)"
        case .invalidWAV:
            return "Arquivo WAV inválido ou vazio para transcrição na nuvem."
        }
    }
}

/// Cloud Speech-to-Text client for Groq, OpenAI, and OpenRouter.
struct CloudTranscriber: Sendable {
    let engine: STTEngine
    let keys: [String]
    let model: String
    let language: String

    private static let maxUploadBytes = 18 * 1024 * 1024 // safely below Groq/OpenAI 25 MB limit
    private static let sampleRate = 16000

    func transcribe(wav: URL, prompt: String? = nil, timeout: Double = 180) async throws -> [WhisperSegment] {
        guard !keys.isEmpty else {
            throw CloudSTTError.noKeys(engine.shortLabel)
        }
        let wavData = try Data(contentsOf: wav)
        guard wavData.count > 44 else { return [] }

        // If full-session WAV exceeds maxUploadBytes (e.g. during retranscribe), split PCM into safe slices.
        if wavData.count > Self.maxUploadBytes {
            return try await transcribeLargeWAV(wavData: wavData, prompt: prompt, timeout: timeout)
        }

        let duration = Double(wavData.count - 44) / Double(Self.sampleRate * 2)
        return try await transcribeWavBytes(wavData, duration: duration, prompt: prompt, timeout: timeout)
    }

    private func transcribeLargeWAV(wavData: Data, prompt: String?, timeout: Double) async throws -> [WhisperSegment] {
        let pcmData = wavData.subdata(in: 44..<wavData.count)
        let bytesPerChunk = (Self.maxUploadBytes - 44) & ~1 // even byte boundary for Int16
        var all: [WhisperSegment] = []
        var offset = 0
        var lastText = prompt

        while offset < pcmData.count {
            let end = min(pcmData.count, offset + bytesPerChunk)
            let slice = pcmData.subdata(in: offset..<end)
            let sampleCount = UInt32(slice.count)
            var chunkWav = WavWriter.header(sampleRate: Self.sampleRate, dataBytes: sampleCount)
            chunkWav.append(slice)

            let startSec = Double(offset) / Double(Self.sampleRate * 2)
            let durSec = Double(slice.count) / Double(Self.sampleRate * 2)
            let segs = try await transcribeWavBytes(chunkWav, duration: durSec, prompt: lastText, timeout: timeout)
            for s in segs {
                all.append(WhisperSegment(start: startSec + s.start, end: startSec + s.end, text: s.text))
            }
            if let last = segs.last?.text {
                lastText = last
            }
            offset = end
        }
        return all
    }

    private func transcribeWavBytes(_ wavData: Data, duration: Double, prompt: String?, timeout: Double) async throws -> [WhisperSegment] {
        switch engine {
        case .openrouter:
            return try await callOpenRouter(wavData: wavData, duration: duration, prompt: prompt, timeout: timeout)
        case .groq:
            return try await callMultipart(
                url: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!,
                providerLabel: "Groq",
                pool: "stt:groq",
                wavData: wavData,
                duration: duration,
                prompt: prompt,
                timeout: timeout
            )
        case .openai:
            return try await callMultipart(
                url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
                providerLabel: "OpenAI",
                pool: "stt:openai",
                wavData: wavData,
                duration: duration,
                prompt: prompt,
                timeout: timeout
            )
        case .local:
            return []
        }
    }

    // MARK: - Groq & OpenAI (multipart/form-data)

    private func callMultipart(
        url: URL,
        providerLabel: String,
        pool: String,
        wavData: Data,
        duration: Double,
        prompt: String?,
        timeout: Double
    ) async throws -> [WhisperSegment] {
        let ordered = KeyRotator.shared.orderedKeys(pool: pool, keys: keys)
        guard !ordered.isEmpty else { throw CloudSTTError.noKeys(providerLabel) }

        var lastErr: Error = CloudSTTError.noKeys(providerLabel)
        for key in ordered {
            do {
                let segs = try await postMultipartOnce(
                    url: url,
                    providerLabel: providerLabel,
                    key: key,
                    wavData: wavData,
                    duration: duration,
                    prompt: prompt,
                    timeout: timeout,
                    includeVerbose: true
                )
                KeyRotator.shared.markSuccess(pool: pool, key: key, allKeys: keys)
                return segs
            } catch CloudSTTError.httpError(let prov, let code, let detail) {
                if code == 400 {
                    // Retry without response_format=verbose_json (e.g. gpt-4o-transcribe uses json)
                    do {
                        let segs = try await postMultipartOnce(
                            url: url,
                            providerLabel: providerLabel,
                            key: key,
                            wavData: wavData,
                            duration: duration,
                            prompt: prompt,
                            timeout: timeout,
                            includeVerbose: false
                        )
                        KeyRotator.shared.markSuccess(pool: pool, key: key, allKeys: keys)
                        return segs
                    } catch CloudSTTError.httpError(let p2, let c2, let d2) {
                        KeyRotator.shared.markFailure(pool: pool, key: key, statusCode: c2)
                        lastErr = CloudSTTError.httpError(p2, c2, d2)
                        continue
                    } catch {
                        KeyRotator.shared.markFailure(pool: pool, key: key, statusCode: 0)
                        lastErr = error
                        continue
                    }
                }
                KeyRotator.shared.markFailure(pool: pool, key: key, statusCode: code)
                lastErr = CloudSTTError.httpError(prov, code, detail)
            } catch {
                KeyRotator.shared.markFailure(pool: pool, key: key, statusCode: 0)
                lastErr = error
            }
        }
        throw lastErr
    }

    private func postMultipartOnce(
        url: URL,
        providerLabel: String,
        key: String,
        wavData: Data,
        duration: Double,
        prompt: String?,
        timeout: Double,
        includeVerbose: Bool
    ) async throws -> [WhisperSegment] {
        let boundary = "MuesliBoundary-\(UUID().uuidString)"
        var body = Data()
        func addField(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }

        addField("model", model)
        addField("temperature", "0")
        if includeVerbose {
            addField("response_format", "verbose_json")
        }
        let lang = normalizedLanguage(language)
        if !lang.isEmpty {
            addField("language", lang)
        }
        if let prompt, !prompt.isEmpty {
            addField("prompt", String(prompt.suffix(200)))
        }

        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"chunk.wav\"\r\n".utf8))
        body.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))
        body.append(wavData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw CloudSTTError.httpError(providerLabel, code, Self.extractError(from: data))
        }
        return Self.parseCloudJSON(data, fallbackDuration: duration)
    }

    // MARK: - OpenRouter (/api/v1/audio/transcriptions JSON + base64 WAV)

    private func callOpenRouter(
        wavData: Data,
        duration: Double,
        prompt: String?,
        timeout: Double
    ) async throws -> [WhisperSegment] {
        let pool = "stt:openrouter"
        let ordered = KeyRotator.shared.orderedKeys(pool: pool, keys: keys)
        guard !ordered.isEmpty else { throw CloudSTTError.noKeys("OpenRouter") }

        let b64 = wavData.base64EncodedString()
        var lastErr: Error = CloudSTTError.noKeys("OpenRouter")

        for key in ordered {
            do {
                let segs = try await postOpenRouterOnce(
                    key: key,
                    b64Audio: b64,
                    duration: duration,
                    prompt: prompt,
                    timeout: timeout,
                    includeVerbose: true
                )
                KeyRotator.shared.markSuccess(pool: pool, key: key, allKeys: keys)
                return segs
            } catch CloudSTTError.httpError(let prov, let code, let detail) {
                if code == 400 {
                    do {
                        let segs = try await postOpenRouterOnce(
                            key: key,
                            b64Audio: b64,
                            duration: duration,
                            prompt: prompt,
                            timeout: timeout,
                            includeVerbose: false
                        )
                        KeyRotator.shared.markSuccess(pool: pool, key: key, allKeys: keys)
                        return segs
                    } catch CloudSTTError.httpError(let p2, let c2, let d2) {
                        KeyRotator.shared.markFailure(pool: pool, key: key, statusCode: c2)
                        lastErr = CloudSTTError.httpError(p2, c2, d2)
                        continue
                    } catch {
                        KeyRotator.shared.markFailure(pool: pool, key: key, statusCode: 0)
                        lastErr = error
                        continue
                    }
                }
                KeyRotator.shared.markFailure(pool: pool, key: key, statusCode: code)
                lastErr = CloudSTTError.httpError(prov, code, detail)
            } catch {
                KeyRotator.shared.markFailure(pool: pool, key: key, statusCode: 0)
                lastErr = error
            }
        }
        throw lastErr
    }

    private func postOpenRouterOnce(
        key: String,
        b64Audio: String,
        duration: Double,
        prompt: String?,
        timeout: Double,
        includeVerbose: Bool
    ) async throws -> [WhisperSegment] {
        let url = URL(string: "https://openrouter.ai/api/v1/audio/transcriptions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("https://github.com/NatanMendes0/muesli-maos", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("Muesli", forHTTPHeaderField: "X-Title")

        var payload: [String: Any] = [
            "model": model,
            "input_audio": [
                "data": b64Audio,
                "format": "wav",
            ],
            "temperature": 0.0,
        ]
        let lang = normalizedLanguage(language)
        if !lang.isEmpty {
            payload["language"] = lang
        }
        if let prompt, !prompt.isEmpty {
            payload["prompt"] = String(prompt.suffix(200))
        }
        if includeVerbose {
            payload["response_format"] = "verbose_json"
        }

        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw CloudSTTError.httpError("OpenRouter", code, Self.extractError(from: data))
        }
        return Self.parseCloudJSON(data, fallbackDuration: duration)
    }

    // MARK: - Response Parsing & Key Validation

    static func parseCloudJSON(_ data: Data, fallbackDuration: Double) -> [WhisperSegment] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if let plain = String(data: data, encoding: .utf8) {
                let cleaned = WhisperTranscriber.clean(plain)
                if !cleaned.isEmpty {
                    return [WhisperSegment(start: 0, end: max(0.5, fallbackDuration), text: cleaned)]
                }
            }
            return []
        }

        var out: [WhisperSegment] = []
        if let segments = obj["segments"] as? [[String: Any]] {
            for s in segments {
                let rawText = (s["text"] as? String) ?? ""
                let cleaned = WhisperTranscriber.clean(rawText)
                guard !cleaned.isEmpty else { continue }
                let start = (s["start"] as? NSNumber)?.doubleValue ?? 0
                let end = (s["end"] as? NSNumber)?.doubleValue ?? max(start + 0.5, fallbackDuration)
                out.append(WhisperSegment(start: start, end: end, text: cleaned))
            }
        }
        if out.isEmpty, let fullText = obj["text"] as? String {
            let cleaned = WhisperTranscriber.clean(fullText)
            if !cleaned.isEmpty {
                out.append(WhisperSegment(start: 0, end: max(0.5, fallbackDuration), text: cleaned))
            }
        }
        return out
    }

    static func validateKeys(engine: STTEngine, keys: [String]) async -> (ok: Bool, message: String) {
        let clean = KeychainHelper.cleanKeys(keys)
        guard !clean.isEmpty else {
            return (false, "Adicione pelo menos uma chave de API.")
        }

        var parts: [String] = []
        var anyOK = false

        for (idx, key) in clean.enumerated() {
            let prefix = "#\(idx + 1)"
            switch engine {
            case .openrouter:
                let url = URL(string: "https://openrouter.ai/api/v1/key")!
                var req = URLRequest(url: url)
                req.timeoutInterval = 10
                req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                do {
                    let (data, resp) = try await URLSession.shared.data(for: req)
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    if code == 200,
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let d = obj["data"] as? [String: Any] {
                        if let rem = d["limit_remaining"] as? NSNumber {
                            let val = rem.doubleValue
                            if val <= 0 {
                                parts.append("\(prefix) ❌ sem crédito ($0)")
                            } else {
                                anyOK = true
                                parts.append(String(format: "%@ ✅ ($%.2f)", prefix, val))
                            }
                        } else {
                            anyOK = true
                            parts.append("\(prefix) ✅ válida")
                        }
                    } else {
                        parts.append("\(prefix) ❌ HTTP \(code)")
                    }
                } catch {
                    parts.append("\(prefix) ❌ \(error.localizedDescription)")
                }
            case .groq, .openai:
                let urlStr = engine == .groq
                    ? "https://api.groq.com/openai/v1/models"
                    : "https://api.openai.com/v1/models"
                var req = URLRequest(url: URL(string: urlStr)!)
                req.timeoutInterval = 10
                req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                do {
                    let (data, resp) = try await URLSession.shared.data(for: req)
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    if code == 200 {
                        anyOK = true
                        parts.append("\(prefix) ✅ válida")
                    } else {
                        parts.append("\(prefix) ❌ HTTP \(code): \(extractError(from: data))")
                    }
                } catch {
                    parts.append("\(prefix) ❌ \(error.localizedDescription)")
                }
            case .local:
                return (true, "Whisper local selecionado")
            }
        }

        return (anyOK, parts.joined(separator: " · "))
    }

    static func fetchOpenRouterSTTModels(key: String?) async -> [String] {
        let urls = [
            "https://openrouter.ai/api/v1/models?output_modalities=transcription",
            "https://openrouter.ai/api/v1/models",
        ]
        for u in urls {
            guard let url = URL(string: u) else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 10
            if let key, !key.isEmpty {
                req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               (resp as? HTTPURLResponse)?.statusCode == 200,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let list = obj["data"] as? [[String: Any]] {
                let ids = list.compactMap { $0["id"] as? String }
                    .filter { id in
                        let low = id.lowercased()
                        return u.contains("output_modalities=transcription")
                            || low.contains("whisper")
                            || low.contains("transcribe")
                    }
                if !ids.isEmpty { return ids }
            }
        }
        return AppSettings.sttOpenRouterModels
    }

    private func normalizedLanguage(_ lang: String) -> String {
        let t = lang.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty || t == "auto" { return "" }
        return t
    }

    private static func extractError(from data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let err = obj["error"] as? [String: Any], let msg = err["message"] as? String { return msg }
            if let msg = obj["error"] as? String { return msg }
            if let msg = obj["message"] as? String { return msg }
        }
        let s = String(data: data.prefix(200), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? "erro desconhecido" : s
    }
}
