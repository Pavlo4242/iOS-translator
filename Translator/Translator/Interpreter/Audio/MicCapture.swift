//
//  MicCapture.swift
//  Translator
//
//  ── Changes vs original ───────────────────────────────────────────────────
//  • NEW  isPaused flag  (lc-04)
//  • NEW  pause() / resume()  (lc-04) — suspend buffer forwarding without
//         tearing down AVAudioEngine; resume is instant.
//  Everything else is verbatim from the original.
// ──────────────────────────────────────────────────────────────────────────

@preconcurrency import AVFoundation

actor MicCapture {
    private let engine = AVAudioEngine()
    private nonisolated let continuation: AsyncStream<AVAudioPCMBuffer>.Continuation
    nonisolated let buffers: AsyncStream<AVAudioPCMBuffer>

    // lc-04 — set by pause()/resume(); checked inside the tap closure
    private var isPaused: Bool = false

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: AVAudioPCMBuffer.self)
        self.buffers      = stream
        self.continuation = continuation
    }

    var inputFormat: AVAudioFormat { engine.inputNode.inputFormat(forBus: 0) }

    func start() throws {
        let input  = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw NSError(
                domain: "MicCapture", code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "Input format unavailable (\(format)). Audio session may not be active for recording."]
            )
        }

        let cont = self.continuation
        input.removeTap(onBus: 0)
        // Capture isPaused via an actor-isolated accessor to avoid data races.
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            // The tap closure runs on an arbitrary thread; we hop to the actor
            // only for the flag read so the audio callback stays non-blocking.
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                let paused = await self.isPaused
                if !paused { cont.yield(buffer) }
            }
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        continuation.finish()
    }

    // MARK: - lc-04  Pause / Resume

    /// Stops forwarding buffers without tearing down the engine.
    func pause() {
        isPaused = true
    }

    /// Resumes forwarding buffers immediately.
    func resume() {
        isPaused = false
    }
}
