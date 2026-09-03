import SwiftUI

/// Controls access to meeting recording and its note-writing model.
struct MeetingsSettingsView: View {
    @Bindable var settings: Settings
    let store: MeetingStore
    let session: MeetingSession
    @Bindable var localLLM: LocalLLMEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection("Meetings") {
                SettingsRow(
                    "Enable meeting recording",
                    description: "Record system audio during a meeting and write notes from it. Needs Screen Recording."
                ) {
                    Toggle("Enable meeting recording", isOn: $settings.meetingsEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(session.isActive)
                }
            }

            if settings.meetingsEnabled {
                SettingsSection("Notes") {
                    if settings.languageModelProvider == .openRouter {
                        SettingsRow(
                            "Model",
                            description: "OpenRouter model that writes the notes. Uses the same API key as transcription."
                        ) {
                            TextField("Required", text: $settings.openRouterNotesModel)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                        }

                        RowDivider()
                    }

                    SettingsRow(
                        "Privacy",
                        description: privacyDescription
                    ) {
                        EmptyView()
                    }
                }

#if DEBUG
                TranscriptNotesSection(settings: settings, store: store, engine: localLLM)
#endif
            }
        }
    }

    /// Where a meeting's transcript goes when notes are made. The engine choice
    /// lives on the Local Models page; this row just tells the truth about the
    /// one that is selected.
    private var privacyDescription: String {
        switch settings.languageModelProvider {
        case .openRouter:
            "The whole transcript is sent to OpenRouter to make notes. Choose a local engine in Local Models to keep it on this Mac."
        case .local:
            "Notes are written on this Mac by \(settings.localModel). The transcript never leaves the machine."
        }
    }
}
