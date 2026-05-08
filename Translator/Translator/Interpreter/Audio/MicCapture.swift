//
//  MicCapture.swift
//  Translator
//
//  Created by Petar Yanakiev on 7.05.26.
//

import AVFoundation

final class MicCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    let buffers: AsyncStream<AVAudioPCMBuffer>

    init() {
        var cont: AsyncStream<AVAudioPCMBuffer>.Continuation!
        self.buffers = AsyncStream { c in cont = c }
        self.continuation = cont
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

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.continuation?.yield(buffer)
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        continuation?.finish()
    }
}
