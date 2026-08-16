import Foundation
import AVFoundation

/// Captures the microphone via AVAudioEngine and emits 16 kHz mono Int16 samples.
/// Optionally enables Apple's voice processing (echo cancellation + noise suppression),
/// which keeps the other side of a speakerphone call out of the "Me" stream.
final class MicRecorder {
    private let engine = AVAudioEngine()
    private let converter = StreamConverter()
    private(set) var voiceProcessingActive = false

    var onSamples: (([Int16]) -> Void)?

    func start(echoCancellation: Bool) throws {
        let input = engine.inputNode

        if echoCancellation {
            do {
                try input.setVoiceProcessingEnabled(true)
                voiceProcessingActive = true
                if #available(macOS 14.0, *) {
                    // Don't let voice processing duck the very system audio we're capturing.
                    input.voiceProcessingOtherAudioDuckingConfiguration =
                        AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
                            enableAdvancedDucking: false,
                            duckingLevel: .min
                        )
                }
            } catch {
                NSLog("Muesli: voice processing unavailable (\(error.localizedDescription)) — recording raw mic")
            }
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            let samples = self.converter.convert(buffer)
            if !samples.isEmpty {
                self.onSamples?(samples)
            }
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        if voiceProcessingActive {
            try? engine.inputNode.setVoiceProcessingEnabled(false)
            voiceProcessingActive = false
        }
    }
}
