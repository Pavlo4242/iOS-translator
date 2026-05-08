//
//  Models.swift
//  Translator
//
//  Created by Petar Yanakiev on 7.05.26.
//

import Foundation

enum Lang {
    static let source = Locale.Language(identifier: "en-US")
    static let target = Locale.Language(identifier: "de-DE")
    static let sourceLocale = Locale(identifier: "en-US")
    static let targetLocale = Locale(identifier: "de-DE")
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
