//
//  Chunker.swift
//  Translator
//
//  Created by Petar Yanakiev on 8.05.26.
//

@preconcurrency import Translation

@MainActor
final class TranslationService {
    private var session: TranslationSession?
    private var pending: [() -> Void] = []

    func bind(_ session: TranslationSession) {
        self.session = session
        let queued = pending
        pending.removeAll()
        for resume in queued {
            resume()
        }
    }

    func translate(_ chunk: Chunk) async throws -> Translated {
        let session = try await waitForSession()
        let response = try await session.translate(chunk.text)
        return Translated(id: chunk.id, sourceText: chunk.text, translatedText: response.targetText)
    }

    private func waitForSession() async throws -> TranslationSession {
        if let session {
            return session
        }

        return try await withCheckedThrowingContinuation { cont in
            pending.append { [weak self] in
                if let session = self?.session {
                    cont.resume(returning: session)
                } else {
                    cont.resume(throwing: CancellationError())
                }
            }
        }
    }
}