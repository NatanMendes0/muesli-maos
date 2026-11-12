import Foundation

/// Serial background worker that turns audio chunks into transcript segments.
/// Chunks arrive during recording (every ~20 s per stream) and drain FIFO;
/// full-file retranscription jobs go through the same path.
actor TranscriptionPipeline {
    private let settings: AppSettings
    private var queue: [TranscriptionJob] = []
    private var draining = false
    /// Tail text of the previous chunk per (meeting, speaker) — used as a Whisper prompt.
    private var context: [String: String] = [:]

    private let onSegments: @Sendable (UUID, [TranscriptSegment], _ replace: Bool) -> Void
    private let onPending: @Sendable (Int) -> Void
    private let onError: @Sendable (String) -> Void

    init(
        settings: AppSettings,
        onSegments: @escaping @Sendable (UUID, [TranscriptSegment], _ replace: Bool) -> Void,
        onPending: @escaping @Sendable (Int) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) {
        self.settings = settings
        self.onSegments = onSegments
        self.onPending = onPending
        self.onError = onError
    }

    var pendingCount: Int { queue.count + (draining ? 1 : 0) }

    func enqueue(_ job: TranscriptionJob) {
        queue.append(job)
        onPending(pendingCount)
        if !draining {
            draining = true
            Task { await drain() }
        }
    }

    private func drain() async {
        while !queue.isEmpty {
            let job = queue.removeFirst()
            onPending(pendingCount)
            await process(job)
            onPending(pendingCount)
        }
        draining = false
        onPending(0)
    }

    private func process(_ job: TranscriptionJob) async {
        struct STTSnapshot: Sendable {
            let engine: STTEngine
            let keys: [String]
            let model: String
            let language: String
            let cloudFallback: Bool
        }

        let snap = await MainActor.run {
            STTSnapshot(
                engine: settings.sttEngine,
                keys: settings.resolvedSTTKeys(),
                model: settings.resolvedSTTModel(),
                language: settings.language,
                cloudFallback: settings.sttCloudFallback
            )
        }

        var localTranscriber: WhisperTranscriber?
        var localInitError: Error?
        if snap.engine == .local || snap.cloudFallback {
            do {
                localTranscriber = try await MainActor.run { try WhisperTranscriber(settings: settings) }
            } catch {
                localInitError = error
            }
        }

        if snap.engine == .local, localTranscriber == nil {
            onError(localInitError?.localizedDescription ?? WhisperError.binaryNotFound.localizedDescription)
            return
        }

        var segments: [TranscriptSegment] = []

        func run(_ url: URL, start: Double, speaker: Speaker) async {
            let contextKey = "\(job.meetingID.uuidString)-\(speaker.rawValue)"
            do {
                let raw: [WhisperSegment]
                if snap.engine != .local {
                    let cloud = CloudTranscriber(
                        engine: snap.engine,
                        keys: snap.keys,
                        model: snap.model,
                        language: snap.language
                    )
                    do {
                        raw = try await cloud.transcribe(
                            wav: url,
                            prompt: job.replaceTranscript ? nil : context[contextKey],
                            timeout: max(180, job.timeout)
                        )
                    } catch {
                        if snap.cloudFallback, let local = localTranscriber {
                            onError("Aviso (\(snap.engine.shortLabel)): \(error.localizedDescription) — usando Whisper local como reserva.")
                            raw = try await local.transcribe(
                                wav: url,
                                prompt: job.replaceTranscript ? nil : context[contextKey],
                                timeout: job.timeout
                            )
                        } else {
                            throw error
                        }
                    }
                } else if let local = localTranscriber {
                    raw = try await local.transcribe(
                        wav: url,
                        prompt: job.replaceTranscript ? nil : context[contextKey],
                        timeout: job.timeout
                    )
                } else {
                    throw localInitError ?? WhisperError.binaryNotFound
                }

                for seg in raw {
                    segments.append(TranscriptSegment(
                        speaker: speaker,
                        start: start + seg.start,
                        end: start + seg.end,
                        text: seg.text
                    ))
                }
                if let lastText = raw.last?.text {
                    context[contextKey] = lastText
                }
            } catch {
                onError(error.localizedDescription)
            }
            if !job.keepFiles {
                try? FileManager.default.removeItem(at: url)
            }
        }

        if let mic = job.micURL { await run(mic, start: job.micStart, speaker: .me) }
        if let sys = job.sysURL { await run(sys, start: job.sysStart, speaker: .them) }

        if !segments.isEmpty || job.replaceTranscript {
            onSegments(job.meetingID, segments.sorted { $0.start < $1.start }, job.replaceTranscript)
        }
    }

    /// Re-runs Whisper over the full-session WAVs in a meeting's folder.
    /// Useful after changing models, or to recover a meeting whose live
    /// transcription was interrupted.
    func retranscribe(meetingID: UUID, folder: URL) {
        var job = TranscriptionJob(meetingID: meetingID)
        let mic = folder.appendingPathComponent("mic.wav")
        let sys = folder.appendingPathComponent("system.wav")
        if FileManager.default.fileExists(atPath: mic.path) { job.micURL = mic }
        if FileManager.default.fileExists(atPath: sys.path) { job.sysURL = sys }
        guard job.micURL != nil || job.sysURL != nil else {
            onError("Nenhum arquivo de áudio foi encontrado para esta reunião.")
            return
        }
        job.keepFiles = true
        job.replaceTranscript = true
        job.timeout = 3600
        enqueue(job)
    }
}
