//
//  RecognitionService.swift
//  Translator
//
//  Created by Petar Yanakiev on 7.05.26.
//

@preconcurrency import AVFoundation
import Speech

actor RecognitionService {
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

    private var eventsContinuation: AsyncStream<RecognitionEvent>.Continuation?
    let events: AsyncStream<RecognitionEvent>

    init() {
        var continuation: AsyncStream<RecognitionEvent>.Continuation!
        self.events = AsyncStream { events in continuation = events }
        self.eventsContinuation = continuation
    }

    func start() async throws {
        // Permission
        let auth = await withCheckedContinuation { (
            continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>
        ) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }

        guard auth == .authorized else {
            throw NSError(domain: "RecognitionService",
                          code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Speech recognition not authorized"])
        }

        let transcriber = SpeechTranscriber(
            locale: Lang.sourceLocale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        self.transcriber = transcriber

        // Ensure on-device assets are installed.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        self.targetFormat = format

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        let (inputSequence, builder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.inputBuilder = builder

        try await analyzer.start(inputSequence: inputSequence)

        // Pump results.
        print("[Recognition] analyzer started. targetFormat=\(String(describing: format))")
        Task { [weak self] in
            guard let self else { return }
            do {
                var resultCount = 0
                for try await result in transcriber.results {
                    resultCount += 1
                    let text = String(result.text.characters)
                    print("[Recognition] result #\(resultCount) isFinal=\(result.isFinal) text=\"\(text)\"")
                    if result.isFinal {
                        await self.eventsContinuation?.yield(.final(text))
                    } else {
                        await self.eventsContinuation?.yield(.partial(text))
                    }
                }
                print("[Recognition] results stream ended after \(resultCount) results")
            } catch {
                print("[Recognition] results stream error: \(error)")
            }
        }
    }

    func ingest(_ buffer: AVAudioPCMBuffer) {
        guard let targetFormat, let inputBuilder else { return }

        if buffer.format == targetFormat {
            inputBuilder.yield(AnalyzerInput(buffer: buffer))
            return
        }

        if converter == nil || converter?.outputFormat != targetFormat {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
        }

        guard let converter else { return }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        // Wrap the supplied boolean in a class to allow mutable capture without concurrent mutation warnings.
        final class SuppliedState: @unchecked Sendable {
            var value = false
        }
        let supplied = SuppliedState()
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, statusPtr in
            if supplied.value {
                statusPtr.pointee = .noDataNow
                return nil
            }
            supplied.value = true
            statusPtr.pointee = .haveData
            return buffer
        }

        if error != nil {
            return
        }

        if status == .error || out.frameLength == 0 {
            return
        }

        inputBuilder.yield(AnalyzerInput(buffer: out))
    }

    func stop() async {
        inputBuilder?.finish()
        inputBuilder = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        analyzer = nil
        transcriber = nil
        eventsContinuation?.finish()
        eventsContinuation = nil
    }
}