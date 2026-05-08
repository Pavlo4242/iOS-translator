//
//  EchoSuppressor.swift
//  Translator
//
//  Created by Petar Yanakiev on 7.05.26.
//

import Foundation

nonisolated final class EchoSuppressor: @unchecked Sendable {
    private struct Entry {
        let text: String
        let timestamp: Date
    }

    private var entries: [Entry] = []
    private let lock = NSLock()
    private let timeToLive: TimeInterval = 12
    private let capacity = 16

    func record(_ text: String) {
        lock.lock()
        entries.append(Entry(text: normalize(text), timestamp: Date()))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
        lock.unlock()
    }

    func shouldSuppress(_ text: String) -> Bool {
        let now = Date()
        let needle = normalize(text)
        guard !needle.isEmpty else { return false }

        lock.lock()
        defer { lock.unlock() }

        entries.removeAll { now.timeIntervalSince($0.timestamp) > timeToLive }
        for entry in entries where entry.text.contains(needle) {
            print("[EchoSuppressor] suppress (substring of \"\(entry.text)\"): \"\(needle)\"")
            return true
        }
        return false
    }

    private func normalize(_ s: String) -> String {
        s.lowercased()
            .components(separatedBy: .punctuationCharacters).joined()
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
