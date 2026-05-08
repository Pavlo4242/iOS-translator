//
//  Chunker.swift
//  Translator
//
//  Created by Petar Yanakiev on 7.05.26.
//

import Foundation

actor Chunker {
    private let pauseThreshold: TimeInterval = 0.6
    private let stableWindow: TimeInterval = 0.8
    private let minChunkChars = 25

    private var committed = ""
    private var lastPartial = ""
    private var lastChange = Date()
    private var lastUnchangedSince = Date()
    private var nextId = 0
    private var idleTask: Task<Void, Never>?

    private let suppressor: EchoSuppressor
    private var continuation: AsyncStream<Chunk>.Continuation?
    nonisolated let chunks: AsyncStream<Chunk>

    init(suppressor: EchoSuppressor) {
        self.suppressor = suppressor
        var c: AsyncStream<Chunk>.Continuation!
        self.chunks = AsyncStream { cont in c = cont }
        self.continuation = c
    }

    func ingest(_ event: RecognitionEvent) {
        switch event {
        case .partial(let text):
            updatePartial(text, isFinal: false)
        case .final(let text):
            updatePartial(text, isFinal: true)
            flushAll()
        }
    }

    func finish() {
        flushAll()
        continuation?.finish()
        continuation = nil
        idleTask?.cancel()
    }

    private func updatePartial(_ text: String, isFinal: Bool) {
        let now = Date()
        let prevPartial = lastPartial
        if text != prevPartial {
            // Did the prefix shared with prevPartial stay stable?
            let stablePrefix = commonPrefix(prevPartial, text)
            if stablePrefix.count < lastStableLength {
                lastUnchangedSince = now    // it shrank/changed; reset stability
            }
            lastPartial = text
            lastChange = now
        }

        // Stable-window check: emit committed → stable prefix if stable enough.
        let elapsed = now.timeIntervalSince(lastUnchangedSince)
        if !isFinal,
           elapsed >= stableWindow,
           let stable = stableEmittable(),
           stable.count >= minChunkChars
        {
            emit(stable)
        }

        rescheduleIdle()
    }

    private var lastStableLength: Int { lastPartial.count }

    private func stableEmittable() -> String? {
        // Take everything past the committed prefix, up to the last hard space (so we don't cut mid-word).
        guard lastPartial.hasPrefix(committed) else { return nil }
        let remaining = String(lastPartial.dropFirst(committed.count))
        guard !remaining.isEmpty else { return nil }
        if let lastSpace = remaining.lastIndex(of: " ") {
            return String(remaining[..<lastSpace]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private func emit(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if suppressor.shouldSuppress(trimmed) {
            committed += text + " "
            return
        }
        let id = nextId; nextId += 1
        continuation?.yield(Chunk(id: id, text: trimmed))
        committed += text + " "
    }

    private func flushAll() {
        guard lastPartial.hasPrefix(committed) else {
            // partial diverged; emit whatever's there.
            let id = nextId; nextId += 1
            let text = lastPartial.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty,
               !suppressor.shouldSuppress(text) {
                continuation?.yield(Chunk(id: id, text: text))
            }
            committed = lastPartial + " "
            return
        }
        let remaining = String(lastPartial.dropFirst(committed.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            if !suppressor.shouldSuppress(remaining) {
                let id = nextId; nextId += 1
                continuation?.yield(Chunk(id: id, text: remaining))
            }
            committed = lastPartial + " "
        }
    }

    private func rescheduleIdle() {
        idleTask?.cancel()
        idleTask = Task { [weak self, pauseThreshold] in
            try? await Task.sleep(nanoseconds: UInt64(pauseThreshold * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            await self.idleFired()
        }
    }

    private func idleFired() {
        flushAll()
    }

    private func commonPrefix(_ a: String, _ b: String) -> String {
        var out = ""
        var ai = a.startIndex, bi = b.startIndex
        while ai < a.endIndex, bi < b.endIndex, a[ai] == b[bi] {
            out.append(a[ai]); a.formIndex(after: &ai); b.formIndex(after: &bi)
        }
        return out
    }
}
