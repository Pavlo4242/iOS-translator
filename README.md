# iOS Translator - Live Interpreter (Duplex) MVP

This is a real-time voice-to-voice interpreter app. User is speaking English, while the app recognizes it, translates to German, and speaks the result back. The whole thing executes while the microphone stays open, so user can keep talking over the playback. Changing the source/translated language is a one-line change inside `Models.swift`.

The project is built entirely on the Apple framework (no 3rd party services, and mostly on-device). Used Apple frameworks: `Speech`(`SpeechAnalyzer`/`SpeechTranscriber`), `Translation` (`TranslationSession`),                                         `AVFoundation` (`AVAudioEngine`, `AVSpeechSynthesizer`). iOS 26 minimum deployment target. Since this is an MVP, the UI is minimalistic, containing a single screen with two text

Testing: Run on a real device for a meaningful test - the simulator's microphone and audio routing are unreliable for duplex. On first launch the app asks for microphone and speech-recognition permission and downloads the on-device speech and translation models, so the first start shows a brief "Preparing..." state.

## How it works?

Audio flows through five stages (MicCapture with PCM buffers -> RecognitionService -> Chunker -> TranslationService -> PlaybackQueue with speaker and EchoSupressor), each running as its own `Task` and connected to the next by an `AsyncStream`. Nothing blocks: recognition keeps running while a translation is being spoken. The whole thing is wired together by `InterpreterCoordinator`, which is the only object the view talks to.