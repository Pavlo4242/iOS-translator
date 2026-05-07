//
//  Models.swift
//  Translator
//
//  Created by Petar Yanakiev on 7.05.26.
//

import Foundation

enum Lang {
    static let source = Locale.Language(identifier: "en-US")
    static let target = Locale.Language(identifier: "bg-BG")
    static let sourceLocale = Locale(identifier: "en-US")
    static let targetLocale = Locale(identifier: "bg-BG")
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
