//
//  ContentView.swift
//  Translator
//
//  ── Changes vs original ───────────────────────────────────────────────────
//  vd-01  ListeningIndicatorView      — animated waveform + pulsing ring
//  vd-02  Dual-panel layout           — separate scrollable source / target panels
//  vd-04  Dynamic Type                — all Text uses semantic .font() styles
//  sf-01  DownloadProgressView        — determinate ProgressView during asset load
//  lc-02  Language swap button        — ⇄ between language labels; calls coordinator
//  lc-03  Clear-transcript button     — trash icon; calls coordinator.clearTranscript()
//  lc-04  Pause / resume button       — mic gate without pipeline teardown
//  th-01  Scrollable timestamped list — LazyVStack rows with relative timestamps
//  th-02  Copy-to-clipboard           — long-press context menu on each row
//  th-03  Share sheet                 — UIActivityViewController for full export
// ──────────────────────────────────────────────────────────────────────────

import SwiftUI
@preconcurrency import Translation

struct ContentView: View {
    @State private var coordinator = InterpreterCoordinator()
    @State private var showShareSheet = false

    // lc-02: local swap toggle so Lang statics can be flipped before restart.
    // The coordinator calls stop()/start() inside swapLanguages().
    @State private var isSwapped = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // sf-01 ── Download progress bar ──────────────────────────────
                if case .downloading(let p) = coordinator.preparePhase {
                    DownloadProgressView(progress: p)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // vd-01 ── Listening indicator ─────────────────────────────────
                ListeningIndicatorView(
                    isListening: coordinator.isRunning && !coordinator.isPaused,
                    isPaused:    coordinator.isPaused,
                    statusText:  coordinator.statusMessage
                )
                .padding(.vertical, 12)

                // lc-02 ── Language bar with swap button ──────────────────────
                LanguageBarView(isSwapped: isSwapped) {
                    isSwapped.toggle()
                    coordinator.swapLanguages()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)

                // vd-02 ── Dual transcript panels ─────────────────────────────
                // th-01 ── Scrollable timestamped list inside each panel ───────
                // th-02 ── Context-menu copy on each row ──────────────────────
                DualPanelView(
                    entries:     coordinator.transcriptEntries,
                    isSwapped:   isSwapped
                )
                .padding(.horizontal, 12)

                Spacer(minLength: 0)

                // ── Bottom toolbar ────────────────────────────────────────────
                BottomBar(
                    coordinator:     coordinator,
                    showShareSheet: $showShareSheet
                )
                .padding()
            }
            .navigationTitle("Interpreter")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .animation(.easeInOut(duration: 0.25), value: coordinator.preparePhase)
            // th-03 ── Share sheet ─────────────────────────────────────────────
            .sheet(isPresented: $showShareSheet) {
                TranscriptShareSheet(entries: coordinator.transcriptEntries)
            }
            .translationTask(coordinator.translationConfig) { session in
                coordinator.bindTranslationSession(session)
                try? await session.prepareTranslation()
            }
        }
    }
}

// MARK: - sf-01  Download progress view --------------------------------------

private struct DownloadProgressView: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                // vd-04: semantic font
                Text("Downloading language models…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.blue)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

// MARK: - vd-01  Animated listening indicator --------------------------------

private struct ListeningIndicatorView: View {
    let isListening: Bool
    let isPaused: Bool
    let statusText: String

    @State private var pulse = false

    private var ringColor: Color {
        if isPaused    { return .orange }
        if isListening { return .blue   }
        return .gray
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Outer pulsing ring (only when actively listening)
                Circle()
                    .stroke(ringColor.opacity(pulse && isListening ? 0 : 0.3), lineWidth: 1.5)
                    .frame(width: 80, height: 80)
                    .scaleEffect(pulse && isListening ? 1.55 : 1)
                    .animation(
                        isListening
                            ? .easeOut(duration: 1.0).repeatForever(autoreverses: false)
                            : .default,
                        value: pulse
                    )

                // Glass disc (vd-01 glassmorphic feel via .ultraThinMaterial)
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 60, height: 60)
                    .overlay(
                        Circle().stroke(ringColor.opacity(0.35), lineWidth: 1)
                    )

                // Waveform bars inside the disc
                WaveformBarsView(active: isListening)
                    .frame(width: 30, height: 20)
            }
            .onAppear  { pulse = isListening }
            .onChange(of: isListening) { _, v in pulse = v }

            // vd-04: .caption2 for the status label
            Text(statusText.isEmpty ? " " : statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel(statusText)
    }
}

private struct WaveformBarsView: View {
    let active: Bool
    @State private var phase = false

    // Heights that animate in a wave when active
    private let baseHeights: [CGFloat] = [0.40, 0.70, 1.00, 0.70, 0.40]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue)
                    .frame(width: 4)
                    .scaleEffect(
                        y: active ? baseHeights[i] : 0.15,
                        anchor: .center
                    )
                    .animation(
                        active
                            ? .easeInOut(duration: 0.40 + Double(i) * 0.06)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.07)
                            : .easeOut(duration: 0.2),
                        value: active
                    )
            }
        }
    }
}

// MARK: - lc-02  Language bar -------------------------------------------------

private struct LanguageBarView: View {
    let isSwapped: Bool
    let onSwap: () -> Void

    // lc-02: source/target labels flip with isSwapped
    private var sourceLabel: String { isSwapped ? "Thai (TH)"   : "English (EN)" }
    private var targetLabel: String { isSwapped ? "English (EN)" : "Thai (TH)"   }

    var body: some View {
        HStack {
            // vd-04: .subheadline for language labels
            Text(sourceLabel)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)

            Button(action: onSwap) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.body)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Swap languages")

            Text(targetLabel)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

// MARK: - vd-02 / th-01 / th-02  Dual transcript panels ----------------------

private struct DualPanelView: View {
    let entries: [TranscriptEntry]
    let isSwapped: Bool

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 8) {
                // Top: source text
                TranscriptPanel(
                    label:     isSwapped ? "Thai (TH)"   : "English (EN)",
                    color:     .blue,
                    entries:   entries,
                    textKey:   \TranscriptEntry.sourceText
                )
                .frame(height: geo.size.height / 2 - 4)

                // Bottom: translated text
                TranscriptPanel(
                    label:     isSwapped ? "English (EN)" : "Thai (TH)",
                    color:     .green,
                    entries:   entries.filter { $0.translatedText != nil },
                    textKey:   \TranscriptEntry.translatedTextOrEmpty
                )
                .frame(height: geo.size.height / 2 - 4)
            }
        }
    }
}

// Small helper so the KeyPath generic stays uniform
private extension TranscriptEntry {
    var translatedTextOrEmpty: String { translatedText ?? "" }
}

private struct TranscriptPanel: View {
    let label:   String
    let color:   Color
    let entries: [TranscriptEntry]
    let textKey: KeyPath<TranscriptEntry, String>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Panel header
            HStack {
                Text(label)
                    .font(.caption.weight(.semibold))      // vd-04
                    .foregroundStyle(color)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.08))

            // th-01 Scrollable timestamped list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if entries.isEmpty {
                            Text("—")
                                .font(.body)               // vd-04
                                .foregroundStyle(.tertiary)
                                .padding(12)
                        } else {
                            ForEach(entries) { entry in
                                TranscriptRowView(
                                    text:      entry[keyPath: textKey],
                                    timestamp: entry.relativeTimeLabel
                                )
                                .id(entry.id)

                                Divider().padding(.leading, 12)
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }
                // Auto-scroll to latest entry
                .onChange(of: entries.last?.id) { _, newID in
                    guard let id = newID else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - th-01 / th-02  Individual transcript row ----------------------------

private struct TranscriptRowView: View {
    let text:      String
    let timestamp: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // vd-04: .body for utterance text
            Text(text.isEmpty ? "…" : text)
                .font(.body)
                .foregroundStyle(text.isEmpty ? .tertiary : .primary)
                .fixedSize(horizontal: false, vertical: true)

            // th-01: relative timestamp
            Text(timestamp)
                .font(.caption2)                           // vd-04
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        // th-02: long-press context menu → copy to clipboard
        .contextMenu {
            Button {
                UIPasteboard.general.string = text
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }
}

// MARK: - Bottom toolbar (lc-03, lc-04, th-03) --------------------------------

private struct BottomBar: View {
    let coordinator: InterpreterCoordinator
    @Binding var showShareSheet: Bool

    var body: some View {
        HStack(spacing: 16) {

            // lc-03  Clear transcript
            Button(role: .destructive) {
                coordinator.clearTranscript()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(coordinator.transcriptEntries.isEmpty)
            .accessibilityLabel("Clear transcript")

            Spacer()

            // Start / Stop (original behaviour preserved)
            Button(coordinator.isRunning ? "Stop" : "Start") {
                coordinator.isRunning ? coordinator.stop() : coordinator.start()
            }
            .buttonStyle(.glassProminent)
            .font(.body.weight(.semibold))                 // vd-04

            // lc-04  Pause / Resume
            if coordinator.isRunning {
                Button {
                    coordinator.togglePause()
                } label: {
                    Image(systemName: coordinator.isPaused ? "mic.fill" : "pause.fill")
                }
                .buttonStyle(.bordered)
                .tint(coordinator.isPaused ? .green : .orange)
                .accessibilityLabel(coordinator.isPaused ? "Resume" : "Pause")
            }

            Spacer()

            // Mute toggle (original)
            HStack(spacing: 4) {
                Toggle("", isOn: Binding(
                    get:  { coordinator.textToSpeechMuted },
                    set:  { coordinator.textToSpeechMuted = $0 }
                ))
                .labelsHidden()
                Text("Mute")
                    .font(.caption)                        // vd-04
            }

            // th-03  Share transcript
            Button {
                showShareSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .disabled(coordinator.transcriptEntries.isEmpty)
            .accessibilityLabel("Share transcript")
        }
    }
}

// MARK: - th-03  Share sheet --------------------------------------------------

private struct TranscriptShareSheet: UIViewControllerRepresentable {
    let entries: [TranscriptEntry]

    private var shareText: String {
        guard !entries.isEmpty else { return "No transcript." }
        let header = "Interpreter Session — \(formattedNow())\n\n"
        let body   = entries.map { $0.shareLine }.joined(separator: "\n")
        return header + body
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}

    private func formattedNow() -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: .now)
    }
}

// MARK: - Preview -------------------------------------------------------------

#Preview {
    ContentView()
}
