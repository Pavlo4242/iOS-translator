//
//  RecognitionService.swift
//  Translator
//
//  Created by Petar Yanakiev on 8.05.26.
//

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
            try await recognition.start()
            try mic.start()
            statusMessage = "Listening"
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
            isRunning = false
            return
        }

        // Recognition
        let micTask = Task { [mic, recognition] in
            for await buffer in mic.buffers {
                if Task.isCancelled { break }
                recognition.ingest(buffer)
            }
        }

        // Chunking (and live source transcript)
        let recogTask = Task { [recognition, chunker, weak self] in
            for await event in recognition.events {
                if Task.isCancelled { break }
                self?.applyRecognitionEvent(event)
                await chunker.ingest(event)
            }
        }

        // Translation -> Playback
        let chunkerStream = chunker.chunks
        let translateTask = Task { [translator, playback, weak self] in
            for await chunk in chunkerStream {
                if Task.isCancelled { break }
                Task { @MainActor in
                    do {
                        let translated = try await translator.translate(chunk)
                        self?.appendTranslated(translated.translatedText)
                        playback.enqueue(translated)
                    } catch {
                        // handle chunking translation failure gracefully
                        print("Chunking translation failed: \(error)")
                    }
                }
            }
        }

        tasks = [micTask, recogTask, translateTask]
    }

    private func applyRecognitionEvent(_ event: RecognitionEvent) {
        switch event {
        case .partial(let text):
            sourceTranscript = text
        case .final(let text):
            sourceTranscript = text
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
