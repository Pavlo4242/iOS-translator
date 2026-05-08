//
//  Chunker.swift
//  Translator
//
//  Created by Petar Yanakiev on 7.05.26.
//

import Foundation

actor Chunker {
    private var nextId = 0
    private let suppressor: EchoSuppressor
    private var continuation: AsyncStream<Chunk>.Continuation?
    nonisolated let chunks: AsyncStream<Chunk>

    init(suppressor: EchoSuppressor) {
        self.suppressor = suppressor
        var c: AsyncStream<Chunk>.Continuation?
        self.chunks = AsyncStream { cont in c = cont }
        self.continuation = c
    }

    func ingest(_ event: RecognitionEvent) async {
        guard case .final(let text) = event else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if await suppressor.shouldSuppress(trimmed) {
            print("[Chunker] suppressed final: \"\(trimmed)\"")
            return
        }

        let lastId = nextId
        nextId += 1
        print("[Chunker] emit chunk #\(lastId): \"\(trimmed)\"")
        continuation?.yield(Chunk(id: lastId, text: trimmed))
    }

    func finish() {
        continuation?.finish()
        continuation = nil
    }
}
