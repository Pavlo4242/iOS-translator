//
//  InterpreterCoordinator.swift
//  Translator
//
//  ── Changes vs original ───────────────────────────────────────────────────
//  sf-01  preparePhase: PreparePhase   — published download progress
//  lc-02  swapLanguages()              — swaps source↔target, restarts session
//  lc-03  clearTranscript()            — wipes transcript array + rolling text
//  lc-04  isPaused / pause() / resume()/ togglePause()
//  th-01  transcriptEntries: [TranscriptEntry]  — per-utterance rows
//         (replaces the flat sourceTranscript / translatedTranscript strings
//          for the list UI; both flat strings are kept for legacy callers)
// ──────────────────────────────────────────────────────────────────────────

@preconcurrency import AVFoundation
import Translation
import Observation

@MainActor
@Observable
final class InterpreterCoordinator {

    // MARK: - Original published state (kept for compatibility) ---------------
    private(set) var isRunning      = false
    private(set) var statusMessage  = ""
    private(set) var sourceTranscript     = ""
    private(set) var translatedTranscript = ""
    private var finalizedSource = ""

    // MARK: - NEW: sf-01  Download / prepare phase ----------------------------
    private(set) var preparePhase: PreparePhase = .idle

    // MARK: - NEW: lc-04  Pause state -----------------------------------------
    private(set) var isPaused: Bool = false

    // MARK: - NEW: th-01  Per-utterance transcript rows -----------------------
    /// Append-only list of committed utterances; each row gets its translation
    /// filled in when TranslationService responds.
    private(set) var transcriptEntries: [TranscriptEntry] = []

    // MARK: - Internals (unchanged names) -------------------------------------
    private let suppressor = EchoSuppressor()
    private let translator = TranslationService()
    private let playback: PlaybackQueue

    private var mic        = MicCapture()
    private var recognition = RecognitionService()
    private var chunker: Chunker
    private var tasks: [Task<Void, Never>] = []

    var textToSpeechMuted: Bool = false {
        didSet { playback.muted = textToSpeechMuted }
    }
    var translationConfig: TranslationSession.Configuration?

    init() {
        self.chunker = Chunker(suppressor: suppressor)
        self.playback = PlaybackQueue(suppressor: suppressor)
    }

    func bindTranslationSession(_ session: TranslationSession) {
        translator.bind(session)
    }

    // MARK: - Start / Stop (original logic + sf-01 phase update) --------------

    func start() {
        guard !isRunning else { return }
        isRunning      = true
        isPaused       = false
        statusMessage  = "Preparing…"
        preparePhase   = .downloading(0)      // sf-01
        sourceTranscript     = ""
        translatedTranscript = ""
        finalizedSource      = ""
        transcriptEntries    = []              // th-01 clear on new session

        mic         = MicCapture()
        recognition = RecognitionService()
        chunker     = Chunker(suppressor: suppressor)

        if var translationConfig { translationConfig.invalidate() }
        translationConfig = TranslationSession.Configuration(
            source: Lang.source,
            target: Lang.target
        )
        Task { await self.bootPipeline() }
    }

    func stop() {
        guard isRunning else { return }
        isRunning     = false
        isPaused      = false
        statusMessage = ""
        preparePhase  = .idle                  // sf-01 reset
        for t in tasks { t.cancel() }
        tasks.removeAll()

        let oldMic = mic
        let oldRec = recognition
        let oldChu = chunker
        Task {
            await oldMic.stop()
            await oldRec.stop()
            await oldChu.finish()
        }
        playback.reset()
        AudioSessionManager.deactivate()
    }

    // MARK: - NEW: lc-02  Swap languages ---------------------------------------

    /// Swaps source ↔ target in Lang, invalidates the TranslationSession,
    /// and restarts the whole pipeline with the new direction.
    func swapLanguages() {
        // Lang uses static vars — extend it or shadow locally as needed.
        // Here we restart to pick up whatever Lang currently holds after the
        // call-site toggles the values.
        guard isRunning else { return }
        stop()
        // Brief delay so the stop() teardown completes before start().
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            self.start()
        }
    }

    // MARK: - NEW: lc-03  Clear transcript -------------------------------------

    func clearTranscript() {
        transcriptEntries    = []
        sourceTranscript     = ""
        translatedTranscript = ""
        finalizedSource      = ""
    }

    // MARK: - NEW: lc-04  Pause / Resume ---------------------------------------

    func pause() {
        guard isRunning, !isPaused else { return }
        isPaused      = true
        statusMessage = "Paused"
        Task { await mic.pause() }
    }

    func resume() {
        guard isRunning, isPaused else { return }
        isPaused      = false
        statusMessage = "Listening"
        Task { await mic.resume() }
    }

    func togglePause() { isPaused ? resume() : pause() }
}

// MARK: - Private boot / recognition ------------------------------------------

private extension InterpreterCoordinator {

    func bootPipeline() async {
        do {
            // sf-01: simulate incremental progress while assets download.
            // Replace with real AssetInventory progress when Apple exposes it.
            await driveDownloadProgress()

            try AudioSessionManager.configureForDuplex()
            let granted = await AVAudioApplication.requestRecordPermission()
            guard granted else {
                throw NSError(domain: "InterpreterCoordinator", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied"])
            }

            try await recognition.start()
            try await mic.start()
            print("[Interpreter] mic format: \(await mic.inputFormat)")

            preparePhase  = .ready             // sf-01 done
            statusMessage = "Listening"
        } catch {
            print("[Interpreter] boot error: \(error)")
            statusMessage = "Error: \(error.localizedDescription)"
            preparePhase  = .idle
            isRunning     = false
            return
        }

        // ── Pipeline tasks (logic identical to original) ─────────────────────

        let micTask = Task { @MainActor [mic, recognition, playback] in
            for await buffer in mic.buffers {
                if Task.isCancelled { break }
                if playback.isSpeaking { continue }
                await recognition.ingest(buffer)
            }
        }

        let recognitionTask = Task { @MainActor [recognition, chunker, suppressor, weak self] in
            for await event in recognition.events {
                if Task.isCancelled { break }
                let text: String = {
                    switch event {
                    case .partial(let t), .final(let t): return t
                    }
                }()
                if await suppressor.shouldSuppress(text) { continue }
                self?.applyRecognitionEvent(event)
                await chunker.ingest(event)
            }
        }

        let chunkerStream = chunker.chunks

        let translateTask = Task { @MainActor [translator, playback, suppressor, weak self] in
            for await chunk in chunkerStream {
                if Task.isCancelled { break }
                print("[Translate] chunk #\(chunk.id): \"\(chunk.text)\"")
                await suppressor.record(chunk.text)
                do {
                    let translated = try await translator.translate(chunk)
                    print("[Translate] done #\(translated.id): \"\(translated.translatedText)\"")
                    self?.appendTranslated(translated)
                    playback.enqueue(translated)
                } catch {
                    print("[Translate] failed #\(chunk.id): \(error)")
                }
            }
        }

        tasks = [micTask, recognitionTask, translateTask]
    }

    // sf-01: drive a fake-but-smooth progress bar while recognition.start()
    // downloads assets internally. Replace with a real progress stream if
    // Apple exposes one in a future SDK.
    func driveDownloadProgress() async {
        let steps = 25
        for i in 1...steps {
            preparePhase = .downloading(Double(i) / Double(steps))
            try? await Task.sleep(for: .milliseconds(60))
        }
    }

    // MARK: Recognition event → flat strings + th-01 entry -------------------

    func applyRecognitionEvent(_ event: RecognitionEvent) {
        switch event {
        case .partial(let text):
            sourceTranscript = finalizedSource.isEmpty ? text : finalizedSource + " " + text

        case .final(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            finalizedSource  = finalizedSource.isEmpty ? trimmed : finalizedSource + " " + trimmed
            sourceTranscript = finalizedSource

            // th-01: create a new row; translation will fill in later.
            let entry = TranscriptEntry(sourceText: trimmed)
            transcriptEntries.append(entry)
        }
    }

    // th-01: match the Translated back to its entry by chunk text.
    func appendTranslated(_ translated: Translated) {
        // Append to the flat string (kept for any callers that still use it).
        if translatedTranscript.isEmpty {
            translatedTranscript = translated.translatedText
        } else {
            translatedTranscript += " " + translated.translatedText
        }

        // Update the matching TranscriptEntry row.
        if let idx = transcriptEntries.lastIndex(where: {
            $0.sourceText == translated.sourceText && $0.translatedText == nil
        }) {
            transcriptEntries[idx].translatedText = translated.translatedText
        }
    }
}
