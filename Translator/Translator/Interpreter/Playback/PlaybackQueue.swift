//
//  RecognitionService.swift
//  Translator
//
//  Created by Petar Yanakiev on 8.05.26.
//

import AVFoundation

@MainActor
final class PlaybackQueue: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var pending: [Int: Translated] = [:]
    private var nextIdToPlay = 0
    private var currentlySpeakingId: Int?

    // True from the moment the play is ready until its
    // didFinish/didCancel callback. Read by the coordinator to gate mic input.
    private(set) nonisolated(unsafe) var isSpeaking: Bool = false

    private let suppressor: EchoSuppressor
    var muted: Bool = false

    init(suppressor: EchoSuppressor) {
        self.suppressor = suppressor
        super.init()
        synth.delegate = self
    }

    func enqueue(_ text: Translated) {
        pending[text.id] = text
        playIfReady()
    }

    func reset() {
        synth.stopSpeaking(at: .immediate)
        pending.removeAll()
        currentlySpeakingId = nil
        nextIdToPlay = 0
        isSpeaking = false
    }

    private func playIfReady() {
        guard currentlySpeakingId == nil,
              let next = pending.removeValue(forKey: nextIdToPlay) else {
            return
        }
        currentlySpeakingId = next.id

        if muted {
            // Skip audio but advance the cursor.
            currentlySpeakingId = nil
            nextIdToPlay += 1
            playIfReady()
            return
        }

        let textToSpeak = next.translatedText
        Task { [suppressor] in await suppressor.record(textToSpeak) }
        isSpeaking = true
        let utterance = AVSpeechUtterance(string: next.translatedText)
        utterance.voice = AVSpeechSynthesisVoice(language: Lang.targetLocale.identifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        self.advance()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        self.advance()
    }

    private func advance() {
        currentlySpeakingId = nil
        isSpeaking = false
        nextIdToPlay += 1
        playIfReady()
    }
}
