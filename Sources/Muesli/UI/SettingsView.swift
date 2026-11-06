import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            AISettingsTab()
                .tabItem { Label("IA", systemImage: "sparkles") }
            TranscriptionSettingsTab()
                .tabItem { Label("Transcrição", systemImage: "waveform") }
            RecordingSettingsTab()
                .tabItem { Label("Gravação", systemImage: "record.circle") }
        }
        .frame(width: 520)
        .padding(.bottom, 4)
    }
}

// MARK: - AI

struct AISettingsTab: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var keyDraft = ""
    @State private var keyLoaded = false
    @State private var testResult: String?
    @State private var testing = false

    private let claudeModels = ["claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5-20251001"]

    var body: some View {
        Form {
            Picker("Provedor", selection: $settings.provider) {
                ForEach(AIProvider.allCases) { p in
                    Text(p.label).tag(p)
                }
            }
            .pickerStyle(.radioGroup)

            switch settings.provider {
            case .anthropic:
                SecureField("Chave da API Anthropic", text: $keyDraft, prompt: Text("sk-ant-…"))
                    .onSubmit(saveKey)
                HStack {
                    Button("Salvar chave", action: saveKey)
                        .disabled(keyDraft == settings.anthropicKey)
                    Text(settings.anthropicKey.isEmpty ? "Nenhuma chave armazenada" : "Chave armazenada no Chaves do macOS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("Modelo", selection: $settings.anthropicModel) {
                    ForEach(claudeModels, id: \.self) { Text($0).tag($0) }
                    if !claudeModels.contains(settings.anthropicModel) {
                        Text(settings.anthropicModel).tag(settings.anthropicModel)
                    }
                }
            case .ollama:
                TextField("URL do Ollama", text: $settings.ollamaBaseURL)
                TextField("Modelo do Ollama", text: $settings.ollamaModel, prompt: Text("llama3.1"))
                Text("Requer o Ollama em execução com o modelo baixado. Tudo é local — nada sai do seu Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .openai:
                TextField("URL-base compatível com OpenAI", text: $settings.openAIBaseURL, prompt: Text("http://localhost:20128/v1"))
                TextField("Modelo", text: $settings.openAIModel, prompt: Text("stack"))
                SecureField("Chave da API", text: $keyDraft)
                    .onSubmit(saveKey)
                HStack {
                    Button("Salvar chave", action: saveKey)
                        .disabled(keyDraft == settings.openAIKey)
                    Text(settings.openAIKey.isEmpty ? "Nenhuma chave armazenada" : "Chave armazenada no Chaves do macOS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button {
                    test()
                } label: {
                    if testing { ProgressView().controlSize(.small) } else { Text("Testar conexão") }
                }
                .disabled(testing)
                if let testResult {
                    Text(testResult)
                        .font(.caption)
                        .foregroundStyle(testResult.hasPrefix("✓") ? Color.green : Color.orange)
                }
            }
        }
        .padding(20)
        .onAppear {
            loadKeyDraft()
        }
        .onChange(of: settings.provider) { _, _ in
            loadKeyDraft()
        }
    }

    private func loadKeyDraft() {
        keyDraft = switch settings.provider {
        case .anthropic: settings.anthropicKey
        case .ollama: ""
        case .openai: settings.openAIKey
        }
        keyLoaded = true
    }

    private func saveKey() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        switch settings.provider {
        case .anthropic: settings.anthropicKey = key
        case .openai: settings.openAIKey = key
        case .ollama: break
        }
    }

    private func test() {
        testing = true
        testResult = nil
        Task {
            defer { testing = false }
            do {
                _ = try await Enhancer(settings: settings).ping()
                testResult = "✓ Connected"
            } catch {
                testResult = error.localizedDescription
            }
        }
    }
}

// MARK: - Transcription

struct TranscriptionSettingsTab: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var downloader = ModelDownloader()

    var body: some View {
        Form {
            LabeledContent("Whisper engine") {
                VStack(alignment: .trailing, spacing: 4) {
                    if let bin = settings.resolveWhisperBinary() {
                        Text(bin.path).font(.caption).foregroundStyle(.green)
                    } else {
                        Text("Não encontrado — brew install whisper-cpp")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            TextField("Caminho personalizado do whisper-cli (opcional)", text: $settings.whisperPathOverride, prompt: Text("/opt/homebrew/bin/whisper-cli"))

            Divider()

            ForEach(WhisperModelInfo.catalog) { model in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.label)
                        Text("\(model.sizeMB) MB").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if ModelDownloader.isDownloaded(model, in: settings.modelsDir) {
                        if settings.modelFileName == model.id {
                            Label("Ativo", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Color.oat)
                                .labelStyle(.titleAndIcon)
                        } else {
                            Button("Usar") { settings.modelFileName = model.id }
                        }
                    } else if downloader.downloading == model.id {
                        ProgressView(value: downloader.progress)
                            .frame(width: 90)
                    } else {
                        Button("Baixar") {
                            downloader.download(model, to: settings.modelsDir)
                        }
                        .disabled(downloader.downloading != nil)
                    }
                }
            }
            if let err = downloader.error {
                Text(err).font(.caption).foregroundStyle(.orange)
            }

            Divider()

            TextField("Idioma", text: $settings.language, prompt: Text("pt ou auto"))
            Text("Use um modelo exclusivo para inglês com \"en\" ou o Large v3 Turbo com \"auto\" para outros idiomas.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}

// MARK: - Recording

struct RecordingSettingsTab: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Toggle("Capturar áudio do sistema (a outra parte da chamada)", isOn: $settings.captureSystemAudio)
            Toggle("Cancelamento de eco no microfone (experimental)", isOn: $settings.echoCancellation)
            Text("Evita que o áudio da chamada reproduzido pelos alto-falantes entre no fluxo \"Eu\". A gravação sempre começa imediatamente com o microfone bruto; o cancelamento de eco é testado em segundo plano e usado apenas se estiver funcionando. Fones de ouvido o tornam desnecessário.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if settings.vpKnownBad {
                Label("O cancelamento de eco falhou neste Mac e será ignorado. Desative e ative novamente para tentar de novo.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Divider()

            LabeledContent("Bloco de transcrição") {
                VStack(alignment: .trailing) {
                    Picker("Duração do bloco", selection: $settings.chunkSeconds) {
                        Text("15 segundos").tag(15.0)
                        Text("30 segundos").tag(30.0)
                        Text("1 minuto").tag(60.0)
                        Text("2 minutos").tag(120.0)
                        Text("3 minutos").tag(180.0)
                        Text("5 minutos").tag(300.0)
                        Text("10 minutos").tag(600.0)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    Text("Menor = transcrição ao vivo mais rápida. Em 10 minutos, o texto pode levar até 10 minutos para aparecer e usa mais memória.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            LabeledContent("Seus dados") {
                Button("Abrir pasta de dados") {
                    NSWorkspace.shared.activateFileViewerSelecting([MeetingStore.defaultBaseDir()])
                }
            }
            Text("Cada reunião é uma pasta comum: meeting.json, notes.md, transcript.md, enhanced.md, mic.wav e system.wav.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}
