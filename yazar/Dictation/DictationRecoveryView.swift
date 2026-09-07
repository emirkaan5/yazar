import SwiftUI

/// Keep the error itself prominent. Secondary recovery choices live in the
/// retry menu instead of turning a short dictation into a dialog.
struct DictationRecoveryView: View {
    @Bindable var yazar: Yazar
    let settings: Settings
    let openSettings: (AppPage) -> Void

    static let width: CGFloat = 420

    private var failure: DictationFailure? {
        if case .error(let failure) = yazar.state { return failure }
        return nil
    }

    private var route: TranscriptionRoute? {
        if case .audio(_, _, let route) = yazar.pendingDictation { return route }
        return nil
    }

    private var isWorking: Bool { yazar.state == .retrying }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if isWorking {
                ProgressView().controlSize(.small).brightness(0.4)
                    .accessibilityLabel("Transcribing")
            } else {
                Image(systemName: failure == nil ? "waveform" : "exclamationmark.triangle.fill")
                    .foregroundStyle(failure == nil ? Color.white : Color.orange)
                    .accessibilityHidden(true)
            }

            // One line is all the capsule has. Longer causes still read in
            // full on hover rather than ending at an ellipsis.
            Text(message)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(message)

            if isWorking {
                Button("Cancel") { yazar.cancel() }
            } else if let route {
                Menu {
                    ForEach(TranscriptionProvider.allCases) { provider in
                        let model = settings.transcription.model(for: provider)
                        Button("Retry with \(modelName(model))") { yazar.retry(using: model) }
                            .help(provider.summary)
                    }
                    Divider()
                    Button("Transcription Settings…") { openSettings(.transcription) }
                    if let page = failure?.settingsPage, page != .transcription {
                        Button("Provider Settings…") { openSettings(page) }
                    }
                    Button("Discard Recording", role: .destructive) { yazar.discardRecovery() }
                } label: {
                    Text("Retry")
                } primaryAction: {
                    yazar.retry(using: route.model)
                }
                .help("Retry the same recording, or choose another provider")
                .fixedSize()
            } else if case .text = yazar.pendingDictation {
                Menu {
                    Button("Discard Text", role: .destructive) { yazar.discardRecovery() }
                } label: {
                    Text("Copy")
                } primaryAction: {
                    yazar.copyRecoveredText()
                }
                .fixedSize()
            } else if let page = failure?.settingsPage {
                Button("Settings…") { openSettings(page) }
            }

            if !isWorking {
                Button("Dismiss", systemImage: "xmark") { yazar.cancel() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.8))
                    .help(failure == nil ? "Hide — reopen from the Yazar menu" : "Discard")
            }
        }
        .font(.system(size: 13, weight: .medium))
        .controlSize(.small)
        .buttonStyle(.bordered)
        .padding(.horizontal, 14)
        .frame(width: Self.width, height: 35)
        .onExitCommand { yazar.cancel() }
    }

    private var message: String {
        if isWorking { return "Transcribing with \(route?.model.provider.displayName ?? "provider")…" }
        if case .text = yazar.pendingDictation {
            return failure?.message ?? "Transcription ready to copy."
        }
        return failure?.message ?? "Recording ready to retry."
    }

    private func modelName(_ model: TranscriptionModel) -> String {
        switch model {
        case .appleSpeech: "Apple Speech · On this Mac"
        case .openRouter(let name): "OpenRouter · \(name)"
        }
    }
}
