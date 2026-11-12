import SwiftUI
import AVFoundation

struct SetupStatus {
    let micGranted: Bool
    let micUndetermined: Bool
    let screenGranted: Bool
    let whisperFound: Bool
    let modelFound: Bool
    let aiReady: Bool

    /// Items that block recording + local transcription entirely.
    var hasBlockers: Bool { !micGranted || !whisperFound || !modelFound }

    @MainActor
    static func current(settings: AppSettings) -> SetupStatus {
        SetupStatus(
            micGranted: Permissions.micStatus == .authorized,
            micUndetermined: Permissions.micStatus == .notDetermined,
            screenGranted: Permissions.screenCaptureGranted,
            whisperFound: settings.resolveWhisperBinary() != nil,
            modelFound: settings.modelURL != nil,
            aiReady: settings.hasAIConfigured
        )
    }
}

/// First-run checklist. Everything Muesli needs, with one button per item.
struct SetupSheet: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var downloader = ModelDownloader()
    @State private var status: SetupStatus?
    @State private var refreshTimer: Timer?

    private let recommendedModel = WhisperModelInfo.catalog[1] // base.en

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("🥣").font(.system(size: 40))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Configurar o Muesli").font(.title2.weight(.semibold))
                    Text("Anotações de reunião locais. Cinco etapas rápidas:")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 16)

            if let s = status {
                VStack(spacing: 10) {
                    SetupRow(
                        done: s.micGranted,
                        title: "Microfone",
                        detail: "Seu lado da conversa (identificado como “Eu”).",
                        actionLabel: s.micUndetermined ? "Permitir" : "Abrir Ajustes"
                    ) {
                        if s.micUndetermined {
                            Task { _ = await Permissions.ensureMicAccess(); refresh() }
                        } else {
                            Permissions.openMicSettings()
                        }
                    }
                    SetupRow(
                        done: s.screenGranted,
                        title: "Áudio do sistema (Gravação de Tela e Áudio do Sistema)",
                        detail: "Os demais participantes (identificados como “Outros”) — capturados diretamente do áudio do Mac, sem bot na chamada. O macOS agrupa isso em Gravação de Tela; depois de ativar, reinicie o Muesli.",
                        actionLabel: "Ativar"
                    ) {
                        if !Permissions.requestScreenCapture() {
                            Permissions.openScreenCaptureSettings()
                        }
                        refresh()
                    }
                    SetupRow(
                        done: s.whisperFound,
                        title: "Mecanismo Whisper",
                        detail: s.whisperFound
                            ? "Encontrado em \(settings.resolveWhisperBinary()?.path ?? "")"
                            : "Instale com o Homebrew: brew install whisper-cpp",
                        actionLabel: "Copiar comando"
                    ) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("brew install whisper-cpp", forType: .string)
                    }
                    SetupRow(
                        done: s.modelFound,
                        title: "Modelo de fala",
                        detail: downloader.downloading != nil
                            ? "Baixando… \(Int(downloader.progress * 100))%"
                            : (s.modelFound ? settings.modelFileName : "\(recommendedModel.label) · \(recommendedModel.sizeMB) MB, download único"),
                        actionLabel: downloader.downloading != nil ? "Baixando…" : "Baixar"
                    ) {
                        downloader.download(recommendedModel, to: settings.modelsDir)
                    }
                    SetupRow(
                        done: s.aiReady,
                        title: "IA para aprimoramento (opcional)",
                        detail: "Groq (gratuito via conta em console.groq.com), Gemini, OpenAI, Claude ou Ollama local — necessário apenas para ✨ Aprimorar e Perguntar. Gravação e transcrição são 100% locais.",
                        actionLabel: "Abrir Ajustes de IA"
                    ) {
                        openAISettings()
                    }
                }
            }

            if let err = downloader.error {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.top, 8)
            }

            HStack {
                Text("Áudio, transcrições e anotações nunca saem deste Mac, exceto quando você aprimora usando um modelo na nuvem.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Concluir") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(.oat)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 16)
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            refresh()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                Task { @MainActor in refresh() }
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    private func refresh() {
        status = SetupStatus.current(settings: settings)
    }

    private func openAISettings() {
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}

struct SetupRow: View {
    let done: Bool
    let title: String
    let detail: String
    let actionLabel: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(done ? Color.green : Color.secondary)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !done {
                Button(actionLabel, action: action)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}
