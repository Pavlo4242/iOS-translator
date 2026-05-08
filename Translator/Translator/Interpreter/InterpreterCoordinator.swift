//
//  RecognitionService.swift
//  Translator
//
//  Created by Petar Yanakiev on 8.05.26.
//

import AVFoundation
import Translation
import Observation

@MainActor
@Observable
final class InterpreterCoordinator {
    private(set) var isRunning = false
    private(set) var statusMessage = ""
    private(set) var sourceTranscript = ""
    private(set) var translatedTranscript = ""
    var textToSpeechMuted: Bool = false {
        didSet {
            playback.muted = textToSpeechMuted
        }
    }

    var translationConfig: TranslationSession.Configuration?

    private let suppressor = EchoSuppressor()
    private let mic = MicCapture()
    private let recognition = RecognitionService()
    private let chunker: Chunker
    private let translator = TranslationService()
    private let playback: PlaybackQueue

    private var tasks: [Task<Void, Never>] = []

    init() {
        self.chunker = Chunker(suppressor: suppressor)
        self.playback = PlaybackQueue(suppressor: suppressor)
    }

    func bindTranslationSession(_ session: TranslationSession) {
        translator.bind(session)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        statusMessage = "Preparing…"
        sourceTranscript = ""
        translatedTranscript = ""
        finalizedSource = ""

        if var translationConfig {
            translationConfig.invalidate()
        }

        translationConfig = TranslationSession.Configuration(
            source: Lang.source,
            target: Lang.target
        )
        Task { await self.bootPipeline() }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        statusMessage = ""
        for t in tasks { t.cancel() }
        tasks.removeAll()
        mic.stop()
        Task { await recognition.stop() }
        Task { await chunker.finish() }
        playback.reset()
        AudioSessionManager.deactivate()
    }

    private func bootPipeline() async {
        do {
            try AudioSessionManager.configureForDuplex()

            // Explicitly request mic record permission before wiring the logic.
            let granted = await AVAudioApplication.requestRecordPermission()
            guard granted else {
                throw NSError(domain: "InterpreterCoordinator", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied"])
            }

            try await recognition.start()
            try mic.start()
            print("[Interpreter] mic format: \(mic.inputFormat)")
            statusMessage = "Listening"
        } catch {
            print("[Interpreter] boot error: \(error)")
            statusMessage = "Error: \(error.localizedDescription)"
            isRunning = false
            return
        }

        let micTask = Task { [mic, recognition, playback] in
            for await buffer in mic.buffers {
                if Task.isCancelled { break }
                if playback.isSpeaking { continue }
                recognition.ingest(buffer)
            }
        }

        let recognitionTask = Task { [recognition, chunker, suppressor, weak self] in
            for await event in recognition.events {
                if Task.isCancelled { break }
                let text: String = {
                    switch event {
                    case .partial(let t), .final(let t): return t
                    }
                }()
                if await suppressor.shouldSuppress(text) {
                    continue
                }
                self?.applyRecognitionEvent(event)
                await chunker.ingest(event)
            }
        }

        let chunkerStream = chunker.chunks

        let translateTask = Task { [translator, playback, suppressor, weak self] in
            for await chunk in chunkerStream {
                if Task.isCancelled { break }
                print("[Translate] received chunk #\(chunk.id): \"\(chunk.text)\"")
                await suppressor.record(chunk.text)
                Task { @MainActor in
                    do {
                        let translated = try await translator.translate(chunk)
                        print("[Translate] done #\(translated.id): \"\(translated.translatedText)\"")
                        self?.appendTranslated(translated.translatedText)
                        playback.enqueue(translated)
                    } catch {
                        print("[Translate] failed #\(chunk.id): \(error)")
                    }
                }
            }
        }

        tasks = [micTask, recognitionTask, translateTask]
    }

    private var finalizedSource = ""

    private func applyRecognitionEvent(_ event: RecognitionEvent) {
        switch event {
        case .partial(let text):
            sourceTranscript = finalizedSource.isEmpty ? text : finalizedSource + " " + text
        case .final(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            finalizedSource = finalizedSource.isEmpty ? trimmed : finalizedSource + " " + trimmed
            sourceTranscript = finalizedSource
        }
    }

    private func appendTranslated(_ text: String) {
        if translatedTranscript.isEmpty {
            translatedTranscript = text
        } else {
            translatedTranscript += " " + text
        }
    }
}
