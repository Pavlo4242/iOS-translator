//
//  Models.swift
//  Translator
//
//  ── Changes vs original ───────────────────────────────────────────────────
//  • Lang / Chunk / Translated / RecognitionEvent  — UNCHANGED
//  • NEW  TranscriptEntry  — paired source+translation row with timestamp;
//                            drives th-01 (list), th-02 (copy), th-03 (share)
//  • NEW  PreparePhase     — model-download progress enum for sf-01
// ──────────────────────────────────────────────────────────────────────────

import Foundation
import AVFoundation

// MARK: - Existing types (verbatim) ------------------------------------------

enum Lang {
    static let source       = Locale.Language(identifier: "en-US")
    static let target       = Locale.Language(identifier: "th-TH")
    static let sourceLocale = Locale(identifier: "en-US")
    static let targetLocale = Locale(identifier: "th-TH")
}

struct Chunk: Sendable, Identifiable {
    let id: Int
    let text: String
}

struct Translated: Sendable, Identifiable {
    let id: Int
    let sourceText: String
    let translatedText: String
}

enum RecognitionEvent: Sendable {
    case partial(String)
    case final(String)
}

// MARK: - NEW: TranscriptEntry  (th-01 / th-02 / th-03) ----------------------

/// One completed utterance row in the transcript list.
/// Created on `.final` recognition and updated once translation arrives.
struct TranscriptEntry: Identifiable {
    let id: UUID
    let sourceText: String
    var translatedText: String?          // nil while translation is pending
    let timestamp: Date

    init(id: UUID = UUID(),
         sourceText: String,
         translatedText: String? = nil,
         timestamp: Date = .now) {
        self.id             = id
        self.sourceText     = sourceText
        self.translatedText = translatedText
        self.timestamp      = timestamp
    }

    /// th-01: compact relative label shown under each row.
    var relativeTimeLabel: String {
        let delta = Int(Date.now.timeIntervalSince(timestamp))
        switch delta {
        case ..<5:    return "just now"
        case ..<60:   return "\(delta)s ago"
        case ..<3600: return "\(delta / 60)m ago"
        default:      return "\(delta / 3600)h ago"
        }
    }

    /// th-03: one line of plain text for the share sheet export.
    var shareLine: String {
        if let t = translatedText { return "\(sourceText) → \(t)" }
        return sourceText
    }
}

// MARK: - NEW: PreparePhase  (sf-01) -----------------------------------------

/// Tracks on-device model download so the UI can show a determinate bar.
enum PreparePhase: Equatable {
    case idle
    case downloading(Double)   // 0.0 … 1.0
    case ready
}
