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

        suppressor.record(next.translatedText)
        let utterance = AVSpeechUtterance(string: next.translatedText)
        utterance.voice = AVSpeechSynthesisVoice(language: Lang.targetLocale.identifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.advance() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.advance() }
    }

    private func advance() {
        currentlySpeakingId = nil
        nextIdToPlay += 1
        playIfReady()
    }
}
