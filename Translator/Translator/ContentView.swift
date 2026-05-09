//
//  ContentView.swift
//  Translator
//
//  Created by Petar Yanakiev on 7.05.26.
//

import SwiftUI
import Translation

struct ContentView: View {
    @State private var coordinator = InterpreterCoordinator()

    var body: some View {
        VStack(spacing: 16) {
            transcriptBox(title: "Source (EN)", text: coordinator.sourceTranscript)
            transcriptBox(title: "Translated (DE)", text: coordinator.translatedTranscript)

            if !coordinator.statusMessage.isEmpty {
                Text(coordinator.statusMessage)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(coordinator.isRunning ? "Stop" : "Start") {
                    coordinator.isRunning ? coordinator.stop() : coordinator.start()
                }
                .buttonStyle(.glassProminent)

                Spacer()

                Toggle("Mute", isOn: $coordinator.textToSpeechMuted)
                    .labelsHidden()
                Text("Mute").font(.caption)
            }
        }
        .padding()
        .translationTask(coordinator.translationConfig) { session in
            coordinator.bindTranslationSession(session)
            try? await session.prepareTranslation()
        }
    }

    private func transcriptBox(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            ScrollView {
                Text(text.isEmpty ? "—" : text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity, alignment: .topLeading)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
        }
    }
}

#Preview {
    ContentView()
}
