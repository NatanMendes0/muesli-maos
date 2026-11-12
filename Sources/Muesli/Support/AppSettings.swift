import Foundation
import SwiftUI
import Combine

enum AppThemeMode: String, CaseIterable, Identifiable {
    case light = "light"
    case dark = "dark"
    case auto = "auto"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return "Claro (padrão)"
        case .dark: return "Escuro"
        case .auto: return "Automático (sistema)"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .auto: return nil
        }
    }
}

enum AIProvider: String, CaseIterable, Identifiable {
    case auto = "auto"
    case groq = "groq"
    case gemini = "gemini"
    case openai = "openai"
    case anthropic = "anthropic"
    case ollama = "ollama"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Automático (melhor disponível)"
        case .groq: return "Groq (Gratuito · Rápido)"
        case .gemini: return "Google Gemini"
        case .openai: return "OpenAI / Compatível"
        case .anthropic: return "Anthropic (Claude)"
        case .ollama: return "Ollama (Local)"
        }
    }
}

/// Persistent preferences. Everything non-secret lives in UserDefaults;
/// API key lists live in the macOS Keychain.
@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("themeMode") var themeModeRaw: String = AppThemeMode.light.rawValue
    @AppStorage("autoEnhanceOnStop") var autoEnhanceOnStop: Bool = true
    @AppStorage("whisperPathOverride") var whisperPathOverride: String = ""
    @AppStorage("modelFileName") var modelFileName: String = "ggml-large-v3-turbo.bin"
    @AppStorage("language") var language: String = "pt"
    @AppStorage("chunkSeconds") var chunkSeconds: Double = 20
    @AppStorage("echoCancellation") var echoCancellation: Bool = true {
        didSet { if vpKnownBad { vpKnownBad = false } }
    }
    @AppStorage("vpKnownBad") var vpKnownBad: Bool = false
    @AppStorage("captureSystemAudio") var captureSystemAudio: Bool = true
    @AppStorage("showConsentNotice") var showConsentNotice: Bool = true
    @AppStorage("consentSnippet") var consentSnippet: String = "Esta reunião está sendo transcrita localmente pelo Muesli."
    @AppStorage("storageBookmark") var storagePath: String = ""

    @AppStorage("aiProvider") var aiProviderRaw: String = AIProvider.auto.rawValue

    // Models & endpoints
    @AppStorage("groqModel") var groqModel: String = "qwen/qwen3.8-27b"
    @AppStorage("geminiModel") var geminiModel: String = "gemini-2.5-flash"
    @AppStorage("openAIModel") var openAIModel: String = "gpt-4o-mini"
    @AppStorage("openAIBaseURL") var openAIBaseURL: String = "https://api.openai.com/v1"
    @AppStorage("anthropicModel") var anthropicModel: String = "claude-haiku-4-5-20251001"
    @AppStorage("ollamaBaseURL") var ollamaBaseURL: String = "http://localhost:11434"
    @AppStorage("ollamaModel") var ollamaModel: String = ""

    var ollamaURL: String {
        get { ollamaBaseURL }
        set { ollamaBaseURL = newValue }
    }

    // Multi-key lists persisted in Keychain
    @Published var groqKeys: [String] {
        didSet { KeychainHelper.saveKeys(groqKeys, account: "groq-api-keys") }
    }
    @Published var geminiKeys: [String] {
        didSet { KeychainHelper.saveKeys(geminiKeys, account: "gemini-api-keys") }
    }
    @Published var openAIKeys: [String] {
        didSet { KeychainHelper.saveKeys(openAIKeys, account: "openai-api-keys") }
    }
    @Published var anthropicKeys: [String] {
        didSet { KeychainHelper.saveKeys(anthropicKeys, account: "anthropic-api-keys") }
    }

    // Convenience single-key bridges for CLI / tests / simple callers
    var groqKey: String {
        get { groqKeys.first ?? "" }
        set { groqKeys = KeychainHelper.cleanKeys([newValue]) }
    }
    var geminiKey: String {
        get { geminiKeys.first ?? "" }
        set { geminiKeys = KeychainHelper.cleanKeys([newValue]) }
    }
    var openAIKey: String {
        get { openAIKeys.first ?? "" }
        set { openAIKeys = KeychainHelper.cleanKeys([newValue]) }
    }
    var anthropicKey: String {
        get { anthropicKeys.first ?? "" }
        set { anthropicKeys = KeychainHelper.cleanKeys([newValue]) }
    }

    var themeMode: AppThemeMode {
        get { AppThemeMode(rawValue: themeModeRaw) ?? .light }
        set { themeModeRaw = newValue.rawValue; objectWillChange.send() }
    }

    var aiProvider: AIProvider {
        get { AIProvider(rawValue: aiProviderRaw) ?? .auto }
        set { aiProviderRaw = newValue.rawValue; objectWillChange.send() }
    }

    init() {
        self.groqKeys = KeychainHelper.loadKeys(account: "groq-api-keys")
        self.geminiKeys = KeychainHelper.loadKeys(account: "gemini-api-keys")
        self.openAIKeys = KeychainHelper.loadKeys(account: "openai-api-keys", fallbackSingleAccount: "openai-api-key")
        self.anthropicKeys = KeychainHelper.loadKeys(account: "anthropic-api-keys", fallbackSingleAccount: "anthropic-api-key")
    }

    var hasGroq: Bool { !KeychainHelper.cleanKeys(groqKeys).isEmpty }
    var hasGemini: Bool { !KeychainHelper.cleanKeys(geminiKeys).isEmpty }
    var hasOpenAI: Bool { !KeychainHelper.cleanKeys(openAIKeys).isEmpty }
    var hasAnthropic: Bool { !KeychainHelper.cleanKeys(anthropicKeys).isEmpty }
    var hasOllama: Bool { !ollamaModel.trimmingCharacters(in: .whitespaces).isEmpty }

    var hasAIConfigured: Bool {
        switch aiProvider {
        case .auto:
            return hasGroq || hasGemini || hasAnthropic || hasOpenAI || hasOllama
        case .groq:
            return hasGroq
        case .gemini:
            return hasGemini
        case .openai:
            return hasOpenAI
        case .anthropic:
            return hasAnthropic
        case .ollama:
            return hasOllama
        }
    }

    var activeProviderSummary: String {
        let p = resolvedActiveProvider()
        switch p {
        case .groq:
            let count = KeychainHelper.cleanKeys(groqKeys).count
            let m = groqModel.isEmpty ? "qwen/qwen3.8-27b" : groqModel
            return "Groq (\(count)x) · \(m)"
        case .gemini:
            let count = KeychainHelper.cleanKeys(geminiKeys).count
            let m = geminiModel.isEmpty ? "gemini-2.5-flash" : geminiModel
            return "Gemini (\(count)x) · \(m)"
        case .openai:
            let m = openAIModel.isEmpty ? "gpt-4o-mini" : openAIModel
            return "OpenAI · \(m)"
        case .anthropic:
            let m = anthropicModel.isEmpty ? "claude-haiku-4-5" : anthropicModel
            return "Claude · \(m)"
        case .ollama:
            let m = ollamaModel.isEmpty ? "Ollama" : ollamaModel
            return "Ollama · \(m)"
        case .auto:
            return "Sem chave de IA (Extrativo)"
        }
    }

    /// Returns the provider that will run first given the current configuration.
    func resolvedActiveProvider() -> AIProvider {
        if aiProvider != .auto { return aiProvider }
        if hasGroq { return .groq }
        if hasGemini { return .gemini }
        if hasAnthropic { return .anthropic }
        if hasOpenAI { return .openai }
        if hasOllama { return .ollama }
        return .auto
    }

    // MARK: - Paths

    var baseDir: URL {
        if !storagePath.isEmpty {
            return URL(fileURLWithPath: storagePath, isDirectory: true)
        }
        return MeetingStore.defaultBaseDir()
    }

    var modelsDir: URL {
        MeetingStore.defaultBaseDir().appendingPathComponent("models", isDirectory: true)
    }

    var modelURL: URL? {
        let url = modelsDir.appendingPathComponent(modelFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static let whisperCandidates = [
        "/opt/homebrew/bin/whisper-cli",
        "/usr/local/bin/whisper-cli",
        "/opt/homebrew/opt/whisper-cpp/bin/whisper-cli",
        "/usr/local/opt/whisper-cpp/bin/whisper-cli",
        "/opt/homebrew/bin/whisper-cpp",
        "/usr/local/bin/whisper-cpp",
    ]

    /// Searches PATH and common Homebrew locations for `whisper-cli` (or legacy `main`).
    func resolveWhisperBinary() -> URL? {
        let fm = FileManager.default
        let override = whisperPathOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            return fm.isExecutableFile(atPath: expanded) ? URL(fileURLWithPath: expanded) : nil
        }
        for path in AppSettings.whisperCandidates where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in envPath.split(separator: ":") {
            let url = URL(fileURLWithPath: String(dir)).appendingPathComponent("whisper-cli")
            if fm.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    /// Model strings are kept in sync across Anthropic/Groq/Gemini/OpenAI.
    static let groqRecommendedModels: [String] = [
        "qwen/qwen3.8-27b",
        "llama-3.3-70b-versatile",
        "llama-3.1-8b-instant",
        "openai/gpt-oss-120b",
    ]

    static let geminiRecommendedModels: [String] = [
        "gemini-2.5-flash",
        "gemini-2.5-pro",
        "gemini-2.5-flash-lite",
    ]

    static let openAIRecommendedModels: [String] = [
        "gpt-4o-mini",
        "gpt-4o",
        "o4-mini",
    ]

    static let anthropicModels: [(id: String, label: String)] = [
        ("claude-haiku-4-5-20251001", "Claude Haiku 4.5 (rápido e econômico)"),
        ("claude-sonnet-4-5", "Claude Sonnet 4.5 (equilibrado)"),
        ("claude-opus-4-1", "Claude Opus 4.1 (máxima qualidade)"),
    ]
}
