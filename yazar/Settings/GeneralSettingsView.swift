import SwiftUI

/// Which provider transcribes, what it needs to do so, and in what language.
struct GeneralSettingsView: View {
    @Bindable var settings: Settings
    @State private var speechModel = AppleSpeechModel()
    @State private var customModel = ""
    @State private var isAddingCustomModel = false
    @FocusState private var customModelFocused: Bool

    var body: some View {
        SettingsSection("Transcription") {
            SettingsRow("Provider", description: settings.transcriptionProvider.summary) {
                Picker("Provider", selection: $settings.transcriptionProvider) {
                    ForEach(TranscriptionProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
                .frame(width: 220, alignment: .trailing)
            }

            if settings.transcriptionProvider.needsAPIKey {
                RowDivider()

                SettingsRow(
                    "API key",
                    description: "Stored securely in your Mac's Keychain."
                ) {
                    SecureField("Required", text: $settings.selectedAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                        .frame(width: 220)
                }

                if let error = settings.apiKeyError {
                    RowDivider()
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
            }

            if settings.transcriptionProvider == .openRouter {
                RowDivider()

                SettingsRow(
                    "Model",
                    description: "OpenRouter model used to transcribe recordings."
                ) {
                    // A Menu rather than a Picker: menu items only carry a
                    // description when their label is two Text views, which a
                    // Picker's tagged items can't be. Toggles draw the
                    // checkmark the pop-up drew for free.
                    Menu {
                        Section("Suggested Models") {
                            ForEach(SuggestedModel.all) { model in
                                Toggle(isOn: selectionOf(model.id)) {
                                    Text(model.id)
                                    Text(model.summary)
                                }
                            }
                        }

                        if !isSuggested(settings.openRouterModel) {
                            Section("Custom Model") {
                                Toggle(isOn: selectionOf(settings.openRouterModel)) {
                                    Text(settings.openRouterModel)
                                }
                            }
                        }

                        Button("Add a Custom Model…") { startAddingCustomModel() }
                    } label: {
                        Text(settings.openRouterModel)
                    }
                    .frame(width: 220)
                    .sheet(isPresented: $isAddingCustomModel) { customModelSheet }
                }
            }

            RowDivider()

            SettingsRow(
                "Language",
                description: settings.transcriptionProvider.languageHint
            ) {
                TextField(settings.transcriptionProvider.languagePlaceholder, text: $settings.language)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }

            if settings.transcriptionProvider == .appleSpeech {
                RowDivider()

                SettingsRow("Language model", description: speechModelDescription) {
                    speechModelControl
                }
            }
        }
        .onAppear { refreshSpeechModel() }
        .onChange(of: settings.transcriptionProvider) { _, _ in refreshSpeechModel() }
        .onChange(of: settings.language) { _, _ in refreshSpeechModel() }
    }

    /// One menu item's checkmark. Re-picking the selected model turns the
    /// toggle off, which should leave the selection alone.
    private func selectionOf(_ model: String) -> Binding<Bool> {
        Binding {
            settings.openRouterModel == model
        } set: { isSelected in
            if isSelected { settings.openRouterModel = model }
        }
    }

    private func isSuggested(_ model: String) -> Bool {
        SuggestedModel.all.contains { $0.id == model }
    }

    // The sheet edits a custom model in place, so it starts from the current
    // one unless that's a suggestion.
    private func startAddingCustomModel() {
        customModel = isSuggested(settings.openRouterModel) ? "" : settings.openRouterModel
        isAddingCustomModel = true
    }

    private var trimmedCustomModel: String {
        customModel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var customModelSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Add a Custom Model")
                    .font(.system(size: 13, weight: .semibold))
                Text("Enter the OpenRouter model string, for example openai/gpt-transcribe.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("provider/model", text: $customModel)
                .textFieldStyle(.roundedBorder)
                .focused($customModelFocused)

            HStack {
                Spacer()
                Button("Cancel") { isAddingCustomModel = false }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    settings.openRouterModel = trimmedCustomModel
                    isAddingCustomModel = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedCustomModel.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { customModelFocused = true }
    }

    private func refreshSpeechModel() {
        guard settings.transcriptionProvider == .appleSpeech else { return }
        speechModel.refresh(language: settings.optionalLanguage)
    }

    /// The resolved locale once Apple Speech accepts the language, so the row
    /// names the model that will run rather than what was typed; the requested
    /// language otherwise, so an unsupported one is still named.
    private var speechModelLanguage: String {
        if let locale = speechModel.locale {
            return AppleSpeechTranscriber.displayName(for: locale)
        }
        return AppleSpeechTranscriber.displayName(for: settings.optionalLanguage)
    }

    private var speechModelDescription: String {
        switch speechModel.state {
        case .checking:
            "Checking the on-device model for \(speechModelLanguage)."
        case .unsupported:
            "Apple Speech has no model for \(speechModelLanguage). Choose another language."
        case .notInstalled:
            "macOS downloads the \(speechModelLanguage) model on first use, or fetch it now."
        case .downloading:
            "Downloading the \(speechModelLanguage) model."
        case .installed:
            "The \(speechModelLanguage) model is on this Mac."
        case .failed(let message):
            message
        }
    }

    @ViewBuilder
    private var speechModelControl: some View {
        switch speechModel.state {
        case .checking, .downloading:
            ProgressView()
                .controlSize(.small)
        case .unsupported:
            Label("Unsupported", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
        case .notInstalled, .failed:
            Button("Download") { speechModel.download() }
                .buttonStyle(.bordered)
        case .installed:
            GrantedLabel("Downloaded")
        }
    }
}
