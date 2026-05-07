//
//  AudioSessionManager.swift
//  Translator
//
//  Created by Petar Yanakiev on 7.05.26.
//

import AVFoundation
import UIKit

enum AudioSessionManager {
    static func configureForDuplex() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
        )
        try session.setActive(true, options: [])
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
