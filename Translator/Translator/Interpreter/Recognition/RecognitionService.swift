//
//  RecognitionService.swift
//  Translator
//
//  Created by Petar Yanakiev on 7.05.26.
//

import AVFoundation
import Speech

final class RecognitionService: @unchecked Sendable {
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
        Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        self.eventsContinuation?.yield(.final(text))
                    } else {
                        self.eventsContinuation?.yield(.partial(text))
                    }
                }
            } catch {
                print("Stream ended / cancelled: \(error)")
            }
        }
    }

    func ingest(_ buffer: AVAudioPCMBuffer) {
        guard let target = targetFormat, let builder = inputBuilder else { return }

        let converted: AVAudioPCMBuffer
        if buffer.format == target {
            converted = buffer
        } else {
            if converter == nil || converter?.outputFormat != target {
                converter = AVAudioConverter(from: buffer.format, to: target)
            }
            guard let conv = converter else { return }
            let ratio = target.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            conv.convert(to: out, error: &error) { _, status in
                if supplied {
                    status.pointee = .noDataNow
                    return nil
                }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            if error != nil { return }
            converted = out
        }

        builder.yield(AnalyzerInput(buffer: converted))
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
