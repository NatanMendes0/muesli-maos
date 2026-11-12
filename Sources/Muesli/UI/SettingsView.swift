import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var updateChecker: UpdateChecker
    @EnvironmentObject private var templateStore: TemplateStore

    @AppStorage("settingsSelectedTab") private var selectedTabRaw: String = SettingsTab.ai.rawValue

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "general"
        case transcription = "transcription"
        case ai = "ai"
        case templates = "templates"
        case recording = "recording"
        case updates = "updates"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "Geral"
            case .transcription: return "Transcrição"
            case .ai: return "Modelos de IA"
            case .templates: return "Modelos de Notas"
            case .recording: return "Gravação"
            case .updates: return "Atualizações"
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .transcription: return "waveform"
            case .ai: return "sparkles"
            case .templates: return "doc.text"
            case .recording: return "mic"
            case .updates: return "arrow.down.circle"
            }
        }
    }

    private var selectedTab: SettingsTab {
        get { SettingsTab(rawValue: selectedTabRaw) ?? .ai }
        nonmutating set { selectedTabRaw = newValue.rawValue }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left tab list (matching Windows Settings modal)
            VStack(alignment: .leading, spacing: 4) {
                Text("Configurações")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(CoastalTheme.text)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)

                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        selectedTabRaw = tab.rawValue
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .frame(width: 16)
                            Text(tab.title)
                                .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .medium))
                            Spacer()
                            if tab == .updates && updateChecker.availableUpdate != nil {
                                Circle().fill(CoastalTheme.infoFg).frame(width: 7, height: 7)
                            }
                        }
                        .foregroundStyle(selectedTab == tab ? CoastalTheme.text : CoastalTheme.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            selectedTab == tab ? CoastalTheme.surface : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(selectedTab == tab ? CoastalTheme.separator : Color.clear, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text("Muesli v\(AppVersion.current)")
                    .font(.caption2)
                    .foregroundStyle(CoastalTheme.faintText)
                    .padding(.horizontal, 10)
            }
            .padding(12)
            .frame(width: 186)
            .background(CoastalTheme.surfaceSoft)

            Rectangle().fill(CoastalTheme.separator).frame(width: 1)

            // Right content scroll area
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .general: GeneralSettingsTab()
                    case .transcription: TranscriptionSettingsTab()
                    case .ai: AISettingsTab()
                    case .templates: TemplatesSettingsTab()
                    case .recording: RecordingSettingsTab()
                    case .updates: UpdatesSettingsTab()
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(CoastalTheme.background)
        }
        .frame(width: 760, height: 580)
    }
}

// MARK: - 1. Geral

private struct GeneralSettingsTab: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: MeetingStore

    var body: some View {
        Text("Geral")
            .font(.title3.weight(.bold))
            .foregroundStyle(CoastalTheme.text)

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Tema da interface")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CoastalTheme.text)
                Picker("", selection: Binding(
                    get: { settings.themeMode },
                    set: { settings.themeMode = $0 }
                )) {
                    ForEach(AppThemeMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            Divider()

            Toggle(isOn: $settings.autoEnhanceOnStop) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aprimorar e gerar título automaticamente ao parar a gravação")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CoastalTheme.text)
                    Text("Assim que os últimos blocos do Whisper terminarem, a IA gera a ata estruturada e renomeia a reunião.")
                        .font(.caption)
                        .foregroundStyle(CoastalTheme.secondaryText)
                }
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pasta de dados")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CoastalTheme.text)
                    Text(store.baseDir.path)
                        .font(.caption)
                        .foregroundStyle(CoastalTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Abrir no Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.meetingsDir])
                }
            }
        }
        .muesliCard()

        HStack {
            Spacer()
            Button("Encerrar Muesli completamente") {
                NSApp.terminate(nil)
            }
            .foregroundStyle(CoastalTheme.danger)
        }
    }
}

// MARK: - 2. Transcrição (Whisper Local)

private struct TranscriptionSettingsTab: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var downloader = ModelDownloader()
    @State private var installed: Set<String> = []

    private let languages: [(code: String, label: String)] = [
        ("pt", "Português (Brasil)"),
        ("auto", "Automático (multilíngue)"),
        ("en", "Inglês"),
        ("es", "Espanhol"),
    ]

    var body: some View {
        Text("Transcrição (Whisper Local)")
            .font(.title3.weight(.bold))
            .foregroundStyle(CoastalTheme.text)

        VStack(alignment: .leading, spacing: 10) {
            let binary = settings.resolveWhisperBinary()
            HStack(spacing: 8) {
                Image(systemName: binary != nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(binary != nil ? CoastalTheme.ok : CoastalTheme.danger)
                Text(binary != nil
                     ? "whisper-cli encontrado em \(binary!.path)"
                     : "whisper-cli não encontrado. Instale com: brew install whisper-cpp")
                    .font(.system(size: 12.5))
                    .foregroundStyle(CoastalTheme.text)
                Spacer()
                if binary == nil {
                    Button("Copiar comando") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("brew install whisper-cpp", forType: .string)
                    }
                    .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Caminho personalizado do whisper-cli (opcional)")
                    .font(.caption)
                    .foregroundStyle(CoastalTheme.secondaryText)
                TextField("/opt/homebrew/bin/whisper-cli", text: $settings.whisperPathOverride)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .muesliCard()

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Idioma da fala")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CoastalTheme.text)
                    Text("Português melhora muito a precisão com Large v3 Turbo.")
                        .font(.caption)
                        .foregroundStyle(CoastalTheme.secondaryText)
                }
                Spacer()
                Picker("", selection: $settings.language) {
                    ForEach(languages, id: \.code) { l in
                        Text(l.label).tag(l.code)
                    }
                }
                .labelsHidden()
                .frame(width: 210)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tamanho do bloco de transcrição")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CoastalTheme.text)
                    Text("Intervalo de corte (em silêncio) para atualizar a transcrição ao vivo.")
                        .font(.caption)
                        .foregroundStyle(CoastalTheme.secondaryText)
                }
                Spacer()
                Picker("", selection: $settings.chunkSeconds) {
                    Text("12 s (rápido)").tag(12.0)
                    Text("20 s (padrão)").tag(20.0)
                    Text("30 s").tag(30.0)
                    Text("45 s (mais contexto)").tag(45.0)
                }
                .labelsHidden()
                .frame(width: 190)
            }
        }
        .muesliCard()

        VStack(alignment: .leading, spacing: 10) {
            Text("Modelos Whisper Locais (ggml)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CoastalTheme.text)

            ForEach(WhisperModelInfo.catalog) { model in
                let isHere = installed.contains(model.id)
                let isSelected = settings.modelFileName == model.id
                let isDownloading = downloader.downloading == model.id

                HStack(spacing: 10) {
                    Button {
                        if isHere { settings.modelFileName = model.id }
                    } label: {
                        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(isHere ? (isSelected ? CoastalTheme.accent : CoastalTheme.secondaryText) : CoastalTheme.faintText)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isHere)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.label)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(CoastalTheme.text)
                        Text("\(model.id) · \(model.sizeMB) MB")
                            .font(.caption)
                            .foregroundStyle(CoastalTheme.secondaryText)
                    }

                    Spacer()

                    if isDownloading {
                        ProgressView(value: downloader.progress)
                            .frame(width: 90)
                        Button("Cancelar") { downloader.cancel() }
                            .controlSize(.small)
                    } else if isHere {
                        if !isSelected {
                            Button("Usar") { settings.modelFileName = model.id }
                                .controlSize(.small)
                        } else {
                            Text("Ativo")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(CoastalTheme.ok)
                        }
                        Button {
                            try? FileManager.default.removeItem(at: settings.modelsDir.appendingPathComponent(model.id))
                            refreshInstalled()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(CoastalTheme.danger)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button("Baixar") {
                            downloader.download(model, to: settings.modelsDir)
                        }
                        .controlSize(.small)
                        .disabled(downloader.downloading != nil)
                    }
                }
                .padding(.vertical, 4)
            }

            if let err = downloader.error {
                Text(err).font(.caption).foregroundStyle(CoastalTheme.danger)
            }
        }
        .muesliCard()
        .onAppear(perform: refreshInstalled)
        .onChange(of: downloader.downloading) { _, _ in refreshInstalled() }
    }

    private func refreshInstalled() {
        var set = Set<String>()
        for m in WhisperModelInfo.catalog where ModelDownloader.isDownloaded(m, in: settings.modelsDir) {
            set.insert(m.id)
        }
        installed = set
    }
}

// MARK: - 3. Modelos de IA (Groq, Gemini, OpenAI, Anthropic, Ollama + Multi-Key)

private struct AISettingsTab: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var ollamaModels: [String] = []
    @State private var testStatus: [AIProvider: String] = [:]
    @State private var testIsError: [AIProvider: Bool] = [:]
    @State private var testingProvider: AIProvider?

    var body: some View {
        Text("Modelos de IA")
            .font(.title3.weight(.bold))
            .foregroundStyle(CoastalTheme.text)

        // Tip card recommending Groq (matching Windows README/UI)
        VStack(alignment: .leading, spacing: 4) {
            Text("💡 Dica: Groq gratuito e ultrarrápido")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(CoastalTheme.infoFg)
            Text("Crie uma conta gratuita em console.groq.com, gere uma ou mais chaves de API (gsk_...) e use o modelo recomendado qwen/qwen3.8-27b. Você também pode combinar Groq, Gemini, OpenAI, Claude ou Ollama local.")
                .font(.caption)
                .foregroundStyle(CoastalTheme.infoFg)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CoastalTheme.infoBg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CoastalTheme.infoBorder, lineWidth: 1))

        // Active Provider selector
        VStack(alignment: .leading, spacing: 8) {
            Text("Provedor ativo para ✨ Aprimorar, Perguntar e Títulos")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CoastalTheme.text)
            Picker("", selection: Binding(
                get: { settings.aiProvider },
                set: { settings.aiProvider = $0 }
            )) {
                ForEach(AIProvider.allCases) { p in
                    Text(p.label).tag(p)
                }
            }
            .labelsHidden()

            if settings.aiProvider == .auto {
                Text("No modo Automático, o Muesli prioriza nesta ordem: Groq → Gemini → Anthropic → OpenAI → Ollama.")
                    .font(.caption)
                    .foregroundStyle(CoastalTheme.secondaryText)
            }
        }
        .muesliCard()

        // GROQ
        ProviderCard(
            title: "Groq (Gratuito / Ultrarrápido)",
            subtitle: "Múltiplas chaves rotacionam automaticamente em caso de limite.",
            provider: .groq,
            testing: testingProvider == .groq,
            status: testStatus[.groq],
            isError: testIsError[.groq] ?? false,
            onTest: { runTest(.groq) }
        ) {
            MultiKeyEditor(
                keys: $settings.groqKeys,
                placeholder: "gsk_..."
            )
            VStack(alignment: .leading, spacing: 4) {
                Text("Modelo Groq")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CoastalTheme.secondaryText)
                TextField("qwen/qwen3.8-27b", text: $settings.groqModel)
                    .textFieldStyle(.roundedBorder)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(AppSettings.groqRecommendedModels, id: \.self) { m in
                            PresetChip(label: m, active: settings.groqModel == m) {
                                settings.groqModel = m
                            }
                        }
                    }
                }
            }
        }

        // GEMINI
        ProviderCard(
            title: "Google Gemini",
            subtitle: "Chaves do Google AI Studio (aistudio.google.com).",
            provider: .gemini,
            testing: testingProvider == .gemini,
            status: testStatus[.gemini],
            isError: testIsError[.gemini] ?? false,
            onTest: { runTest(.gemini) }
        ) {
            MultiKeyEditor(
                keys: $settings.geminiKeys,
                placeholder: "AIza..."
            )
            VStack(alignment: .leading, spacing: 4) {
                Text("Modelo Gemini")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CoastalTheme.secondaryText)
                TextField("gemini-2.5-flash", text: $settings.geminiModel)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 6) {
                    ForEach(AppSettings.geminiRecommendedModels, id: \.self) { m in
                        PresetChip(label: m, active: settings.geminiModel == m) {
                            settings.geminiModel = m
                        }
                    }
                }
            }
        }

        // OPENAI / COMPATIBLE
        ProviderCard(
            title: "OpenAI (ou API compatível / 9router / OpenRouter)",
            subtitle: "Compatível com OpenAI, OpenRouter (https://openrouter.ai/api/v1) ou 9router local.",
            provider: .openai,
            testing: testingProvider == .openai,
            status: testStatus[.openai],
            isError: testIsError[.openai] ?? false,
            onTest: { runTest(.openai) }
        ) {
            MultiKeyEditor(
                keys: $settings.openAIKeys,
                placeholder: "sk-..."
            )
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Base URL")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(CoastalTheme.secondaryText)
                    TextField("https://api.openai.com/v1", text: $settings.openAIBaseURL)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Modelo")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(CoastalTheme.secondaryText)
                    TextField("gpt-4o-mini", text: $settings.openAIModel)
                        .textFieldStyle(.roundedBorder)
                }
            }
            HStack(spacing: 6) {
                ForEach(AppSettings.openAIRecommendedModels, id: \.self) { m in
                    PresetChip(label: m, active: settings.openAIModel == m) {
                        settings.openAIModel = m
                    }
                }
            }
        }

        // ANTHROPIC
        ProviderCard(
            title: "Anthropic (Claude)",
            subtitle: "Chaves da Anthropic armazenadas com segurança no Keychain do macOS.",
            provider: .anthropic,
            testing: testingProvider == .anthropic,
            status: testStatus[.anthropic],
            isError: testIsError[.anthropic] ?? false,
            onTest: { runTest(.anthropic) }
        ) {
            MultiKeyEditor(
                keys: $settings.anthropicKeys,
                placeholder: "sk-ant-..."
            )
            VStack(alignment: .leading, spacing: 4) {
                Text("Modelo Claude")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CoastalTheme.secondaryText)
                Picker("", selection: $settings.anthropicModel) {
                    ForEach(AppSettings.anthropicModels, id: \.id) { m in
                        Text(m.label).tag(m.id)
                    }
                }
                .labelsHidden()
            }
        }

        // OLLAMA
        ProviderCard(
            title: "Ollama (Totalmente Local)",
            subtitle: "Executa 100% offline neste Mac sem enviar dados para a nuvem.",
            provider: .ollama,
            testing: testingProvider == .ollama,
            status: testStatus[.ollama],
            isError: testIsError[.ollama] ?? false,
            onTest: { runTest(.ollama) }
        ) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("URL do Servidor")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(CoastalTheme.secondaryText)
                    TextField("http://localhost:11434", text: $settings.ollamaBaseURL)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Modelo Ollama")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(CoastalTheme.secondaryText)
                    HStack(spacing: 6) {
                        TextField("qwen3:8b", text: $settings.ollamaModel)
                            .textFieldStyle(.roundedBorder)
                        Button("Listar") {
                            Task { ollamaModels = await Enhancer.fetchOllamaModels(baseURL: settings.ollamaBaseURL) }
                        }
                        .controlSize(.small)
                    }
                }
            }
            if !ollamaModels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(ollamaModels, id: \.self) { m in
                            PresetChip(label: m, active: settings.ollamaModel == m) {
                                settings.ollamaModel = m
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            Task { ollamaModels = await Enhancer.fetchOllamaModels(baseURL: settings.ollamaBaseURL) }
        }
    }

    private func runTest(_ provider: AIProvider) {
        testingProvider = provider
        testStatus[provider] = "Testando…"
        testIsError[provider] = false
        Task {
            defer { testingProvider = nil }
            do {
                let res = try await Enhancer(settings: settings).testProvider(provider)
                testStatus[provider] = "✅ \(res)"
                testIsError[provider] = false
            } catch {
                testStatus[provider] = "❌ \(error.localizedDescription)"
                testIsError[provider] = true
            }
        }
    }
}

private struct ProviderCard<Content: View>: View {
    let title: String
    let subtitle: String
    let provider: AIProvider
    let testing: Bool
    let status: String?
    let isError: Bool
    let onTest: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(CoastalTheme.text)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(CoastalTheme.secondaryText)
                }
                Spacer()
                Button(action: onTest) {
                    if testing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Text("Testar")
                    }
                }
                .controlSize(.small)
                .disabled(testing)
            }

            content

            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(isError ? CoastalTheme.danger : CoastalTheme.ok)
                    .textSelection(.enabled)
            }
        }
        .muesliCard()
    }
}

private struct MultiKeyEditor: View {
    @Binding var keys: [String]
    let placeholder: String
    @State private var reveal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Chaves de API (Keychain)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CoastalTheme.secondaryText)
                Spacer()
                Button(reveal ? "Ocultar" : "Mostrar") {
                    reveal.toggle()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(CoastalTheme.infoFg)
            }

            let displayIndices = keys.isEmpty ? [0] : Array(keys.indices)
            ForEach(displayIndices, id: \.self) { idx in
                HStack(spacing: 6) {
                    Text("#\(idx + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(CoastalTheme.faintText)
                        .frame(width: 24, alignment: .leading)

                    Group {
                        if reveal {
                            TextField(placeholder, text: binding(for: idx))
                        } else {
                            SecureField(placeholder, text: binding(for: idx))
                        }
                    }
                    .textFieldStyle(.roundedBorder)

                    if keys.count > 1 || (keys.count == 1 && !keys[0].isEmpty) {
                        Button {
                            removeKey(at: idx)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(CoastalTheme.danger)
                        }
                        .buttonStyle(.plain)
                        .help("Remover chave")
                    }
                }
            }

            Button {
                if keys.isEmpty {
                    keys = ["", ""]
                } else {
                    keys.append("")
                }
            } label: {
                Label("Adicionar outra chave de API", systemImage: "plus.circle")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(CoastalTheme.accent)
            .padding(.top, 2)
        }
    }

    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { index < keys.count ? keys[index] : "" },
            set: { newVal in
                var copy = keys
                while copy.count <= index { copy.append("") }
                copy[index] = newVal
                keys = copy
            }
        )
    }

    private func removeKey(at index: Int) {
        var copy = keys
        guard index < copy.count else { return }
        copy.remove(at: index)
        keys = copy
    }
}

private struct PresetChip: View {
    let label: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption2.weight(active ? .semibold : .regular))
                .foregroundStyle(active ? CoastalTheme.btnInkFg : CoastalTheme.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(active ? CoastalTheme.btnInkBg : CoastalTheme.surfaceSoft, in: Capsule())
                .overlay(Capsule().stroke(CoastalTheme.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 4. Modelos de Notas (Templates)

private struct TemplatesSettingsTab: View {
    @EnvironmentObject private var templateStore: TemplateStore
    @State private var name = ""
    @State private var desc = ""
    @State private var sectionsText = "Resumo Executivo: Principais conclusões\nDecisões: Tudo o que foi acordado\nPlano de Ação: Tarefas, responsáveis e prazos"

    var body: some View {
        Text("Modelos de Notas (Templates)")
            .font(.title3.weight(.bold))
            .foregroundStyle(CoastalTheme.text)

        VStack(alignment: .leading, spacing: 10) {
            Text("Modelos Padrão")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CoastalTheme.text)
            ForEach(MeetingTemplate.builtin) { tpl in
                VStack(alignment: .leading, spacing: 2) {
                    Text(tpl.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CoastalTheme.text)
                    Text(tpl.description)
                        .font(.caption)
                        .foregroundStyle(CoastalTheme.secondaryText)
                }
                .padding(.vertical, 2)
            }
        }
        .muesliCard()

        VStack(alignment: .leading, spacing: 10) {
            Text("Seus Modelos Personalizados")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CoastalTheme.text)

            if templateStore.customTemplates.isEmpty {
                Text("Nenhum modelo personalizado criado ainda.")
                    .font(.caption)
                    .foregroundStyle(CoastalTheme.secondaryText)
            } else {
                ForEach(templateStore.customTemplates) { tpl in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tpl.name).font(.system(size: 13, weight: .medium)).foregroundStyle(CoastalTheme.text)
                            Text("\(tpl.sections.count) seções").font(.caption).foregroundStyle(CoastalTheme.secondaryText)
                        }
                        Spacer()
                        Button {
                            templateStore.deleteCustom(id: tpl.id)
                        } label: {
                            Image(systemName: "trash").foregroundStyle(CoastalTheme.danger)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            Text("Criar novo modelo")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CoastalTheme.text)
            TextField("Nome (ex.: Comitê de TI)", text: $name)
                .textFieldStyle(.roundedBorder)
            TextField("Descrição curta", text: $desc)
                .textFieldStyle(.roundedBorder)
            Text("Seções (uma por linha, formato `Título: instrução`):")
                .font(.caption)
                .foregroundStyle(CoastalTheme.secondaryText)
            TextEditor(text: $sectionsText)
                .font(.system(size: 12, design: .monospaced))
                .frame(height: 80)
                .padding(6)
                .background(CoastalTheme.surfaceSoft, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(CoastalTheme.separator, lineWidth: 1))

            Button("Salvar modelo") {
                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let secs = sectionsText.components(separatedBy: .newlines).compactMap { line -> TemplateSection? in
                    let t = line.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return nil }
                    let parts = t.split(separator: ":", maxSplits: 1)
                    let title = String(parts[0]).trimmingCharacters(in: .whitespaces)
                    let hint = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
                    return title.isEmpty ? nil : TemplateSection(title: title, hint: hint)
                }
                guard !trimmedName.isEmpty, !secs.isEmpty else { return }
                let tpl = MeetingTemplate(
                    id: "custom_\(UUID().uuidString.prefix(8))",
                    name: trimmedName,
                    description: desc.trimmingCharacters(in: .whitespacesAndNewlines),
                    sections: secs,
                    isBuiltin: false
                )
                templateStore.saveCustom(tpl)
                name = ""
                desc = ""
            }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .muesliCard()
    }
}

// MARK: - 5. Gravação

private struct RecordingSettingsTab: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Text("Gravação e Áudio")
            .font(.title3.weight(.bold))
            .foregroundStyle(CoastalTheme.text)

        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $settings.captureSystemAudio) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Capturar áudio do sistema (ScreenCaptureKit)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CoastalTheme.text)
                    Text("Registra os outros participantes da chamada como “Outros”.")
                        .font(.caption)
                        .foregroundStyle(CoastalTheme.secondaryText)
                }
            }

            Divider()

            Toggle(isOn: $settings.echoCancellation) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cancelamento de eco (Voice Processing)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CoastalTheme.text)
                    Text("Evita que a voz das caixas de som entre no seu microfone como “Eu”.")
                        .font(.caption)
                        .foregroundStyle(CoastalTheme.secondaryText)
                }
            }

            Divider()

            Toggle(isOn: $settings.showConsentNotice) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Exibir lembrete de consentimento ao gravar")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CoastalTheme.text)
                }
            }
            if settings.showConsentNotice {
                TextField("Texto do lembrete", text: $settings.consentSnippet)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .muesliCard()

        VStack(alignment: .leading, spacing: 8) {
            Text("Permissões do macOS")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CoastalTheme.text)
            HStack(spacing: 10) {
                Button("Ajustes de Microfone") { Permissions.openMicSettings() }
                Button("Gravação de Tela e Áudio") { Permissions.openScreenCaptureSettings() }
            }
        }
        .muesliCard()
    }
}

// MARK: - 6. Atualizações

private struct UpdatesSettingsTab: View {
    @EnvironmentObject private var updateChecker: UpdateChecker

    var body: some View {
        Text("Atualizações")
            .font(.title3.weight(.bold))
            .foregroundStyle(CoastalTheme.text)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Muesli para macOS")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CoastalTheme.text)
                    Text("Versão instalada: v\(AppVersion.current)")
                        .font(.caption)
                        .foregroundStyle(CoastalTheme.secondaryText)
                }
                Spacer()
                Button {
                    Task { await updateChecker.check(interactive: true) }
                } label: {
                    HStack(spacing: 5) {
                        if updateChecker.checking { ProgressView().controlSize(.mini) }
                        Text(updateChecker.checking ? "Verificando…" : "🔄 Verificar atualizações")
                    }
                }
                .disabled(updateChecker.checking)
            }

            Divider()

            if let info = updateChecker.availableUpdate {
                VStack(alignment: .leading, spacing: 8) {
                    Text("🎉 Nova versão disponível: \(info.latestVersion)")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(CoastalTheme.ok)

                    ScrollView {
                        Text(info.releaseNotes)
                            .font(.caption)
                            .foregroundStyle(CoastalTheme.bodyText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(maxHeight: 150)
                    .background(CoastalTheme.surfaceSoft, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(CoastalTheme.separator, lineWidth: 1))

                    if updateChecker.downloading {
                        ProgressView(value: updateChecker.downloadProgress)
                        Text("Baixando \(info.zipName)… \(Int(updateChecker.downloadProgress * 100))%")
                            .font(.caption)
                            .foregroundStyle(CoastalTheme.secondaryText)
                    }

                    HStack(spacing: 10) {
                        Button("⬇️ Baixar Nova Versão (.zip)") {
                            updateChecker.downloadUpdate()
                        }
                        .disabled(updateChecker.downloading)

                        Button("🌐 Ver no GitHub") {
                            updateChecker.openReleasePage()
                        }
                    }

                    if let fileURL = updateChecker.downloadedFileURL {
                        Text("✅ Baixado em \(fileURL.path). Extraia e substitua o Muesli.app na pasta Aplicativos!")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CoastalTheme.ok)
                    }
                }
            } else if let okMsg = updateChecker.upToDateMessage {
                Text("✅ \(okMsg)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CoastalTheme.ok)
            } else if let err = updateChecker.errorMessage {
                Text("❌ \(err)")
                    .font(.caption)
                    .foregroundStyle(CoastalTheme.danger)
            } else {
                Text("Clique no botão acima para verificar se há novas versões disponíveis no GitHub.")
                    .font(.caption)
                    .foregroundStyle(CoastalTheme.secondaryText)
            }
        }
        .muesliCard()
    }
}
