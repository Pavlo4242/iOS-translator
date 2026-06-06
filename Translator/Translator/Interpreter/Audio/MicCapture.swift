//
//  MicCapture.swift
//  Translator
//
//  Created by Petar Yanakiev on 7.05.26.
//

@preconcurrency import AVFoundation

actor MicCapture {
    private let engine = AVAudioEngine()
    private nonisolated let continuation: AsyncStream<AVAudioPCMBuffer>.Continuation
    let buffers: AsyncStream<AVAudioPCMBuffer>

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: AVAudioPCMBuffer.self)
        self.buffers = stream
        self.continuation = continuation
    }

    var inputFormat: AVAudioFormat { engine.inputNode.inputFormat(forBus: 0) }

    func start() throws {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.channelCount > 0,
              format.sampleRate > 0 else {
            throw NSError(
                domain: "MicCapture",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "Input format unavailable (\(format)). Audio session may not be active for recording."]
            )
        }

        let continuationStream = self.continuation
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            continuationStream.yield(buffer)
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        continuation.finish()
    }
}