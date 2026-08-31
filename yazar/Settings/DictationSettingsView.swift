import SwiftUI

/// How a dictation is captured and what it sounds like.
struct DictationSettingsView: View {
    @Bindable var settings: Settings
    let yazar: Yazar
    @State private var isRecordingTrigger = false

    private var audioInputs: [AudioInput] { AudioInput.available }

    var body: some View {
        SettingsSection("Recording") {
            SettingsRow(
                "Dictation key",
                description: "Hold \(settings.dictationTrigger.displayName) to record."
            ) {
                Button("Change…") { isRecordingTrigger = true }
                    .buttonStyle(.bordered)
                    .sheet(isPresented: $isRecordingTrigger) {
                        TriggerRecorderSheet(
                            trigger: $settings.dictationTrigger,
                            yazar: yazar
                        )
                    }
            }

            RowDivider()

            SettingsRow(
                "Audio input",
                description: "Microphone used for dictation."
            ) {
                Picker("Audio input", selection: $settings.audioInputID) {
                    if !settings.audioInputID.isEmpty,
                       !audioInputs.contains(where: { $0.id == settings.audioInputID }) {
                        Text("Unavailable device").tag(settings.audioInputID)
                    }
                    ForEach(audioInputs) { input in
                        Text(input.name).tag(input.id)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }

            RowDivider()

            SettingsRow(
                "Restore clipboard",
                description: "Put back what you had copied after pasting a transcription."
            ) {
                Toggle("Restore clipboard", isOn: $settings.restoreClipboard)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            RowDivider()

            SettingsRow(
                "Play sounds",
                description: "Play feedback for recording and transcription status."
            ) {
                Toggle("Play sounds", isOn: $settings.playSounds)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            RowDivider()

            SettingsRow(
                "Sound theme",
                description: "Sounds used for start, stop, cancellation, and transcription errors."
            ) {
                Picker("Sound theme", selection: $settings.soundTheme) {
                    ForEach(SoundTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .labelsHidden()
                .frame(width: 220, alignment: .trailing)
                .disabled(!settings.playSounds)
            }

#if DEBUG
            RowDivider()

            SettingsRow(
                "Demo mode",
                description: "Use the microphone, wait five seconds, then paste sample text."
            ) {
                Toggle("Demo mode", isOn: $settings.demoMode)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            RowDivider()

            SettingsRow(
                "Error mode",
                description: "Show the error state used when transcription fails."
            ) {
                Button("Trigger error mode") { yazar.triggerDemoError() }
                    .buttonStyle(.bordered)
            }
#endif
        }
    }
}
