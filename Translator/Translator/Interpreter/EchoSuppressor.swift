//
//  EchoSuppressor.swift
//  Translator
//
//  Created by Petar Yanakiev on 7.05.26.
//

import Foundation

final class EchoSuppressor: @unchecked Sendable {
    private struct Entry {
        let text: String
        let timestamp: Date
    }

    private var entries: [Entry] = []
    private let lock = NSLock()
    private let timeToLive: TimeInterval = 30
    private let capacity = 10

    func record(_ text: String) {
        lock.lock()
        entries.append(Entry(text: normalize(text), timestamp: Date()))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
        lock.unlock()
    }

    func shouldSuppress(_ text: String) -> Bool {
        let now = Date()
        let normalizedText = normalize(text)
        guard !normalizedText.isEmpty else { return false }
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll { now.timeIntervalSince($0.timestamp) > timeToLive }
        for entry in entries {
            if entry.text.contains(normalizedText) || normalizedText.contains(entry.text) {
                return true
            }

            if tokenOverlap(entry.text, normalizedText) >= 0.6 {
                return true
            }
        }
        return false
    }

    private func normalize(_ s: String) -> String {
        s.lowercased()
            .components(separatedBy: .punctuationCharacters).joined()
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func tokenOverlap(_ a: String, _ b: String) -> Double {
        let ta = Set(a.split(separator: " "))
        let tb = Set(b.split(separator: " "))
        guard !ta.isEmpty, !tb.isEmpty else { return 0 }
        let inter = ta.intersection(tb).count
        return Double(inter) / Double(min(ta.count, tb.count))
    }
}
