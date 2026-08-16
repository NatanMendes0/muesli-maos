import Foundation

/// Hidden CLI entry points used for headless verification:
///
///     Muesli --selftest              storage round-trip, wav writer, parser checks
///     Muesli --transcribe file.wav   run the app's whisper path on a file
///     Muesli --enhance-test          ping the configured AI provider (key from env or keychain)
///     Muesli --version
enum MuesliCLI {
    static func runIfNeeded() -> Bool {
        let args = CommandLine.arguments
        if args.contains("--version") {
            print("Muesli 0.1.0")
            return true
        }
        if args.contains("--selftest") {
            return selftest()
        }
        if let i = args.firstIndex(of: "--transcribe"), args.count > i + 1 {
            return transcribe(path: args[i + 1])
        }
        if args.contains("--enhance-test") {
            return enhanceTest()
        }
        return false
    }

    // MARK: - Self test

    private static func selftest() -> Bool {
        var failures: [String] = []

        // 1. WAV round trip: header must describe the payload exactly.
        do {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("muesli-selftest.wav")
            let samples = (0..<16000).map { Int16(truncatingIfNeeded: $0 &* 7) }
            try WavWriter.write(samples: samples, to: tmp)
            let data = try Data(contentsOf: tmp)
            if data.count != 44 + 32000 { failures.append("wav size \(data.count) != 32044") }
            let rate = data.subdata(in: 24..<28).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            if UInt32(littleEndian: rate) != 16000 { failures.append("wav rate wrong") }
            try FileManager.default.removeItem(at: tmp)
        } catch {
            failures.append("wav: \(error)")
        }

        // 2. Meeting JSON round trip. (Whole-second dates: ISO8601 has no sub-second precision.)
        do {
            var m = Meeting(title: "Test", createdAt: Date(timeIntervalSince1970: 1_755_000_000), folderName: "t")
            m.transcript = [TranscriptSegment(speaker: .me, start: 1, end: 2, text: "hello")]
            m.chat = [ChatMessage(role: "user", text: "hi", date: Date(timeIntervalSince1970: 1_755_000_100))]
            let data = try JSONEncoder.muesli.encode(m)
            let back = try JSONDecoder.muesli.decode(Meeting.self, from: data)
            if back != m { failures.append("meeting codable mismatch") }
        } catch {
            failures.append("codable: \(error)")
        }

        // 3. Whisper JSON parsing.
        do {
            let sample = #"{"transcription":[{"offsets":{"from":0,"to":2500},"text":" Hello world."},{"offsets":{"from":2500,"to":3000},"text":" [BLANK_AUDIO]"}]}"#
            let segs = try WhisperTranscriber.parse(json: Data(sample.utf8))
            if segs.count != 1 || segs[0].text != "Hello world." || segs[0].end != 2.5 {
                failures.append("whisper parse wrong: \(segs)")
            }
        } catch {
            failures.append("whisper parse: \(error)")
        }

        // 4. Transcript coalescing.
        let segs: [TranscriptSegment] = [
            .init(speaker: .me, start: 0, end: 2, text: "One."),
            .init(speaker: .me, start: 3, end: 5, text: "Two."),
            .init(speaker: .them, start: 6, end: 8, text: "Three."),
        ]
        let groups = segs.coalesced()
        if groups.count != 2 || groups[0].text != "One. Two." {
            failures.append("coalesce wrong: \(groups)")
        }

        if failures.isEmpty {
            print("SELFTEST OK")
            return true
        } else {
            print("SELFTEST FAILED:\n" + failures.joined(separator: "\n"))
            exit(1)
        }
    }

    // MARK: - Transcribe a file through the app's own pipeline code

    private static func transcribe(path: String) -> Bool {
        let sem = DispatchSemaphore(value: 0)
        Task {
            do {
                let settings = AppSettings()
                let transcriber = try WhisperTranscriber(settings: settings)
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                let segments = try await transcriber.transcribe(wav: url, timeout: 600)
                for s in segments {
                    print("[\(formatClock(s.start))-\(formatClock(s.end))] \(s.text)")
                }
                if segments.isEmpty { print("(no speech detected)") }
            } catch {
                print("ERROR: \(error.localizedDescription)")
                exit(1)
            }
            sem.signal()
        }
        sem.wait()
        return true
    }

    // MARK: - Enhance connectivity test

    private static func enhanceTest() -> Bool {
        let sem = DispatchSemaphore(value: 0)
        Task {
            let settings = AppSettings()
            if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !envKey.isEmpty {
                settings.anthropicKey = envKey
            }
            do {
                let reply = try await Enhancer(settings: settings).ping()
                print("ENHANCE OK: \(reply)")
            } catch {
                print("ENHANCE ERROR: \(error.localizedDescription)")
                exit(1)
            }
            sem.signal()
        }
        sem.wait()
        return true
    }
}
