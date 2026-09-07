#if DEBUG
import SwiftUI

/// Presents every current dictation failure through the production state owner.
struct DebugErrorsView: View {
    let yazar: Yazar
    @State private var selectedFailure = DictationFailure.transcription(.serviceUnavailable)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Error", selection: $selectedFailure) {
                Section("Recording") {
                    Text("Microphone unavailable").tag(DictationFailure.recorder(.microphoneUnavailable))
                    Text("Capture setup failed").tag(DictationFailure.recorder(.captureSetupFailed))
                    Text("Capture interrupted").tag(DictationFailure.recorder(.captureInterrupted))
                }

                Section("System") {
                    Text("Dictation key unavailable").tag(DictationFailure.hotKey(.eventTapUnavailable))
                    Text("Clipboard unavailable").tag(DictationFailure.clipboardUnavailable)
                }

                Section("Transcription") {
                    Text("Missing credentials").tag(DictationFailure.transcription(.credentials))
                    Text("Access denied").tag(DictationFailure.transcription(.accessDenied))
                    Text("Payment required").tag(DictationFailure.transcription(.paymentRequired))
                    Text("Rate limited").tag(DictationFailure.transcription(.rateLimited))
                    Text("Service unavailable").tag(DictationFailure.transcription(.serviceUnavailable))
                    Text("Network unavailable").tag(DictationFailure.transcription(.network))
                    Text("Timed out").tag(DictationFailure.transcription(.timedOut))
                    Text("Invalid response").tag(DictationFailure.transcription(.invalidResponse))
                    Text("Invalid model").tag(DictationFailure.transcription(.invalidModel))
                    Text("Unsupported language")
                        .tag(DictationFailure.transcription(.unsupportedLanguage("Turkish")))
                    Text("Apple Speech unavailable").tag(DictationFailure.transcription(.unavailable))
                    Text("Empty text").tag(DictationFailure.transcription(.emptyText))
                    Text("Unknown").tag(DictationFailure.transcription(.unknown))
                    Text("HTTP status").tag(DictationFailure.transcription(.http(418)))
                }
            }
            .pickerStyle(.menu)

            Text(selectedFailure.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)

            HStack {
                Spacer()
                Button(
                    "Trigger Error",
                    systemImage: "bolt.trianglebadge.exclamationmark",
                    action: trigger
                )
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
    }

    private func trigger() {
        yazar.show(selectedFailure)
    }
}
#endif
